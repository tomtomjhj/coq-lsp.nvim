local util = require('coq-lsp.util')
local render = require('coq-lsp.render')

---@class CoqLSPNvim
---@field lc lsp.Client
---@field buffers table<buffer, { info_bufnr: buffer, cancel_goals?: fun() }>
---@field debounce_timer uv_timer_t
---@field config coqlsp.config
---@field progress_ns integer
---@field ag integer
local CoqLSPNvim = {}
CoqLSPNvim.__index = CoqLSPNvim

---@type string[] command names
local commands = {}

---@param client lsp.Client
---@param config coqlsp.config
function CoqLSPNvim:new(client, config)
  local new = {}
  new.lc = client
  new.buffers = {}
  new.debounce_timer = assert(vim.loop.new_timer(), 'Could not create timer')
  new.config = config
  new.progress_ns = vim.api.nvim_create_namespace('coq-lsp-progress-' .. client.id)
  new.ag = vim.api.nvim_create_augroup('coq-lsp-' .. client.id, { clear = true })
  return setmetatable(new, self)
end

local CoqFileProgressKind = {
  Processing = 1,
  FatalError = 2,
}

local progress_highlight_kind = {
  [CoqFileProgressKind.Processing] = 'CoqtailSent',
  [CoqFileProgressKind.FatalError] = 'Error',
}

---@param result coqlsp.CoqFileProgressParams
function CoqLSPNvim:fileProgress(result)
  local bufnr = vim.uri_to_bufnr(result.textDocument.uri)
  vim.api.nvim_buf_clear_namespace(bufnr, self.progress_ns, 0, -1)
  -- TODO: Highlight is very noisy when typing. Use sign or something else.
  for _, info in ipairs(result.processing) do
    local kind = info.kind or CoqFileProgressKind.Processing
    vim.highlight.range(
      bufnr,
      self.progress_ns,
      progress_highlight_kind[kind],
      util.position_lsp_to_api(bufnr, info.range['start'], self.lc.offset_encoding),
      util.position_lsp_to_api(bufnr, info.range['end'], self.lc.offset_encoding),
      { priority = vim.highlight.priorities.user }
    )
  end
end

---@param bufnr buffer
function CoqLSPNvim:create_info_panel(bufnr)
  local info_bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[info_bufnr].filetype = 'coq-goals'
  self.buffers[bufnr].info_bufnr = info_bufnr
end

---@param bufnr buffer
function CoqLSPNvim:get_info_bufnr(bufnr)
  local info_bufnr = self.buffers[bufnr].info_bufnr
  if info_bufnr and vim.api.nvim_buf_is_valid(info_bufnr) then
    return info_bufnr
  end
  self:create_info_panel(bufnr)
  return self.buffers[bufnr].info_bufnr
end

---@param bufnr? buffer
function CoqLSPNvim:open_info_panel(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.cmd.sbuffer {
    args = { self:get_info_bufnr(bufnr) },
    -- TODO: customization
    -- See `:h nvim_parse_cmd`. Note that the "split size" is `range`.
    mods = { keepjumps = true, keepalt = true, vertical = true, split = 'belowright' },
  }
  vim.cmd.clearjumps()
  vim.api.nvim_set_current_win(win)
end

commands[#commands + 1] = 'open_info_panel'

---@param answer coqlsp.GoalAnswer
---@param position MarkPosition Don't use answer.position because buffer content may have changed.
function CoqLSPNvim:show_goals(answer, position)
  local bufnr = vim.uri_to_bufnr(answer.textDocument.uri)
  local info_bufnr = self:get_info_bufnr(bufnr)

  local wins = {} ---@type table<window, vim.fn.winsaveview.ret>
  for _, win in ipairs(vim.fn.win_findbuf(info_bufnr) or {}) do
    vim.api.nvim_win_call(win, function()
      wins[win] = vim.fn.winsaveview()
    end)
  end

  local lines = render.GoalAnswer(answer, position)
  vim.api.nvim_buf_set_lines(info_bufnr, 0, -1, false, lines)

  for win, view in pairs(wins) do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  end
end

---@param bufnr? buffer registered buffer
---@param position? MarkPosition
function CoqLSPNvim:goals_async(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  position = position or util.guess_position(bufnr)
  local cancel_old = self.buffers[bufnr].cancel_goals
  if cancel_old then
    self.buffers[bufnr].cancel_goals = nil
    cancel_old()
  end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = util.make_position_params(bufnr, position, self.lc.offset_encoding),
  }
  local cancel = util.request_async(self.lc, bufnr, 'proof/goals', params, function(err, result)
    self.buffers[bufnr].cancel_goals = nil
    if err then
      return
    end
    self:show_goals(result, position)
  end)
  self.buffers[bufnr].cancel_goals = cancel
end

function CoqLSPNvim:goals_async_debounced()
  -- NOTE: Stopping the timer doesn't touch already scheduled callbacks.
  self.debounce_timer:stop()
  self.debounce_timer:start(
    self.config.goals_debounce,
    0,
    vim.schedule_wrap(function()
      local bufnr = vim.api.nvim_get_current_buf()
      if self.buffers[bufnr] then
        self:goals_async(bufnr)
      end
    end)
  )
end

---@param bufnr? buffer registered buffer
---@param position? MarkPosition
function CoqLSPNvim:goals_sync(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  position = position or util.guess_position(bufnr)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = util.make_position_params(bufnr, position, self.lc.offset_encoding),
  }
  local request_result, err = self.lc.request_sync('proof/goals', params, 500, bufnr)
  if err then
    vim.notify('goals_sync() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then
    return
  end
  self:show_goals(request_result.result, position)
end

---@param bufnr? buffer
function CoqLSPNvim:get_document(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }
  local request_result, err = self.lc.request_sync('coq/getDocument', params, 500, bufnr)
  if err then
    vim.notify('get_document() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then
    return
  end
  return request_result.result
end

---@param bufnr? buffer
function CoqLSPNvim:saveVo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }
  local request_result, err = self.lc.request_sync('coq/saveVo', params, 500, bufnr)
  if err then
    vim.notify('saveVo() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then
    vim.notify(
      ('saveVo() failed:\n%s'):format(vim.inspect(request_result.err)),
      vim.log.levels.ERROR
    )
    return
  end
  vim.notify(('saved %s'):format(params.textDocument.uri .. 'o'))
end
commands[#commands + 1] = 'saveVo'

---@param bufnr buffer
function CoqLSPNvim:unregister(bufnr)
  assert(self.buffers[bufnr])
  vim.api.nvim_buf_clear_namespace(bufnr, self.progress_ns, 0, -1)
  vim.api.nvim_clear_autocmds { group = self.ag, buffer = bufnr }
  if self.buffers[bufnr].info_bufnr then
    vim.api.nvim_buf_delete(self.buffers[bufnr].info_bufnr, { force = true })
  end
  self.buffers[bufnr] = nil
end

---@param bufnr buffer
function CoqLSPNvim:register(bufnr)
  assert(self.buffers[bufnr] == nil)
  self.buffers[bufnr] = {}
  self:create_info_panel(bufnr)
  self:open_info_panel(bufnr)

  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = self.ag,
    buffer = bufnr,
    desc = 'Request proof/goals on cursor movement',
    callback = function()
      self:goals_async_debounced()
    end,
  })
  -- nvim bug? If the current coq buf is the only valid buffer and I bwipeout
  -- that buffer, this buffer is newly added to buffer list.
  vim.api.nvim_create_autocmd({ 'BufDelete', 'LspDetach' }, {
    group = self.ag,
    buffer = bufnr,
    desc = 'Unregister deleted/detached buffer',
    callback = function(ev)
      self:unregister(ev.buf)
    end,
  })

  vim.api.nvim_buf_create_user_command(bufnr, 'CoqLsp', function(opts)
    self:command(opts.args)
  end, {
    bang = true,
    nargs = 1,
    complete = function(arglead, _, _)
      return vim.tbl_filter(function(command)
        return command:find(arglead) ~= nil
      end, commands)
    end,
  })

  self:goals_async(bufnr)
end

---@param args string
function CoqLSPNvim:command(args)
  local _, to, subcommand = args:find('([%w_]+)%s*')
  if not vim.tbl_contains(commands, subcommand) then
    error(('"%s" is not a valid CoqLsp command'):format(subcommand))
  end
  args = args:sub(to + 1)
  -- TODO: check validity of args? maybe add some spec to commands. Maybe a pattern?
  CoqLSPNvim[subcommand](self, #args > 0 and args or nil)
end

function CoqLSPNvim:dispose()
  self.debounce_timer:stop()
  self.debounce_timer:close()
  for bufnr, _ in pairs(self.buffers) do
    self:unregister(bufnr)
  end
  vim.api.nvim_clear_autocmds { group = self.ag }
end

return CoqLSPNvim
