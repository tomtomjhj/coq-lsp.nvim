-- Suppress warnings about private methods of lsp.Client. <https://github.com/neovim/neovim/pull/22509>
---@diagnostic disable: invisible

-- nvim types {{{

--- Position for indexing used by most API functions (0-based line, 0-based column) (:h api-indexing).
---@class APIPosition: { [1]: integer, [2]: integer }

--- Position for "mark-like" indexing (1-based line, 0-based column) (:h api-indexing).
---@class MarkPosition: { [1]: integer, [2]: integer }

-- }}}

-- LSP types {{{

---@class Position
---@field line integer
---@field character integer

---@class Range
---@field start Position
---@field end Position

-- Corresponds to LSP's PositionEncodingKind
---@alias OffsetEncoding "utf-8"|"utf-16"|"utf-32"

-- }}}

-- coq-lsp types {{{

---@alias Pp string|any

---@class Hyp
---@field names Pp[]
---@field def? Pp
---@field ty Pp

---@class Goal
---@field hyps Hyp[]
---@field ty Pp

---@class GoalConfig
---@field goals Goal[];
---@field stack (Goal[])[];
---@field bullet? Pp;
---@field shelf Goal[];
---@field given_up Goal[];

---@class Message
---@field range? Range
---@field level number
---@field text Pp

---@class GoalAnswer
---@field textDocument table: VersionedTextDocumentIdentifier
---@field position Position
---@field goals? GoalConfig
---@field messages any[] | Message[]
---@field error? Pp

-- }}}

-- utils {{{

---@param bufnr buffer
---@param position Position
---@param offset_encoding OffsetEncoding
---@return APIPosition
local function position_lsp_to_api(bufnr, position, offset_encoding)
  local idx = vim.lsp.util._get_line_byte_from_position(
    bufnr,
    { line = position.line, character = position.character },
    offset_encoding
  )
  return { position.line, idx }
end

---@param bufnr buffer
---@param position MarkPosition
---@param offset_encoding OffsetEncoding
---@return Position
local function make_position_params(bufnr, position, offset_encoding)
  local row, col = unpack(position)
  row = row - 1
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, true)[1]
  if not line then
    return { line = 0, character = 0 }
  end

  col = vim.lsp.util._str_utfindex_enc(line, col, offset_encoding)

  return { line = row, character = col }
end

---@param bufnr buffer
---@return MarkPosition
local function guess_position(bufnr)
  local win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_get_buf(win) ~= bufnr then
    error("can't guess position")
  end
  return vim.api.nvim_win_get_cursor(win)
end

---@param client lsp.Client
---@param bufnr integer
---@param method string
---@param params table
---@param handler? lsp-handler
---@return fun()|nil cancel function to cancel the request
local function request_async(client, bufnr, method, params, handler)
  local request_success, request_id = client.request(method, params, handler, bufnr)
  if request_success then
    return function()
      client.cancel_request(assert(request_id))
    end
  end
end

-- }}}

-- Assume that coq-lsp LSP client is unique.
---@type CoqLSPNvim?
local the_client

---@class CoqLSPNvimConfig
---@field goals_debounce integer
---@field show_goals_on "manual"|"cursor"

---@type CoqLSPNvimConfig
local default_config = {
  -- TODO: implement it; should be dynamically configurable
  show_goals_on = "cursor",
  goals_debounce = 150,
}

---@class CoqLSPNvim
---@field lc lsp.Client
---@field buffers table<buffer, { info_bufnr: buffer, cancel_goals?: fun() }>
---@field debounce_timer uv_timer_t
---@field config CoqLSPNvimConfig
---@field progress_ns integer
---@field ag integer
local CoqLSPNvim = {}
CoqLSPNvim.__index = CoqLSPNvim

---@param client lsp.Client
function CoqLSPNvim:new(client)
  local new = {}
  new.lc = client
  new.buffers = {}
  new.debounce_timer = assert(vim.loop.new_timer(), 'Could not create timer')
  new.config = default_config
  new.progress_ns = vim.api.nvim_create_namespace('coq-lsp-progress-' .. client.id)
  new.ag = vim.api.nvim_create_augroup("coq-lsp-" .. client.id, { clear = true })
  return setmetatable(new, self)
end

local CoqFileProgressKind = {
  Processing = 1,
  FatalError = 2
}

local progress_highlight_kind = {
  [CoqFileProgressKind.Processing] = 'CoqtailSent',
  [CoqFileProgressKind.FatalError] = 'Error',
}

---@type lsp-handler
local function file_progress_handler(_, result, _, _)
  assert(the_client)
  local bufnr = vim.uri_to_bufnr(result.textDocument.uri)
  vim.api.nvim_buf_clear_namespace(bufnr, the_client.progress_ns, 0, -1)
  -- TODO: Highlight is very noisy when typing. Use sign or something else.
  for _, info in ipairs(result.processing) do
    local kind = info.kind or CoqFileProgressKind.Processing
    vim.highlight.range(
      bufnr,
      the_client.progress_ns,
      progress_highlight_kind[kind],
      position_lsp_to_api(bufnr, info.range['start'], the_client.lc.offset_encoding),
      position_lsp_to_api(bufnr, info.range['end'], the_client.lc.offset_encoding),
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

-- TODO: Render goals nicely.
-- * see also lean.nvim infoview stuff
-- * handle multi-line pp
-- * different types for Pp (pp_type)
---@param i integer
---@param n integer
---@param goal Goal
---@return string
local function render_goal(i, n, goal)
  local lines = {}
  lines[#lines+1] = 'Goal ' .. i .. ' / ' .. n
  for _, hyp in ipairs(goal.hyps) do
    local line = table.concat(hyp.names, ', ') .. ' : ' .. hyp.ty
    if hyp.def then
      line = line .. ' := ' .. hyp.def
    end
    lines[#lines+1] = line
  end
  lines[#lines+1] = ''
  lines[#lines+1] = '========================================'
  lines[#lines+1] = ''
  lines[#lines+1] = goal.ty
  return table.concat(lines, '\n')
end

---@param answer GoalAnswer
---@param position MarkPosition Don't use answer.position because buffer content may have changed.
function CoqLSPNvim:show_goals(answer, position)
  local bufnr = vim.uri_to_bufnr(answer.textDocument.uri)
  local goal_config = answer.goals or {}
  local goals = goal_config.goals or {}
  local rendered = {}
  for i, goal in ipairs(goals) do
    rendered[#rendered+1] = render_goal(i, #goals, goal)
  end
  local lines = {}
  lines[#lines+1] = vim.fn.bufname(bufnr) .. ':' .. position[1] .. ':' .. (position[2] + 1)
  -- NOTE: each Pp can contain newline, which isn't allowed by nvim_buf_set_lines
  vim.list_extend(lines, vim.split(table.concat(rendered, '\n\n\n────────────────────────────────────────────────────────────\n'), '\n'))
  vim.api.nvim_buf_set_lines(self:get_info_bufnr(bufnr), 0, -1, false, lines)
end

---@param bufnr? buffer registered buffer
---@param position? MarkPosition
function CoqLSPNvim:goals_async(bufnr, position)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  position = position or guess_position(bufnr)
  local cancel_old = self.buffers[bufnr].cancel_goals
  if cancel_old then
    self.buffers[bufnr].cancel_goals = nil
    cancel_old()
  end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = make_position_params(bufnr, position, self.lc.offset_encoding)
  }
  local cancel = request_async(self.lc, bufnr, 'proof/goals', params, function(err, result)
    self.buffers[bufnr].cancel_goals = nil
    if err then return end
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
  position = position or guess_position(bufnr)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = make_position_params(bufnr, position, self.lc.offset_encoding)
  }
  local request_result, err = self.lc.request_sync('proof/goals', params, 500, bufnr)
  if err then
    vim.notify('goals_sync() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then return end
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
  if request_result.err then return end
  return request_result.result
end


---@param bufnr? buffer
function CoqLSPNvim:save_vo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }
  local request_result, err = self.lc.request_sync('coq/saveVo', params, 500, bufnr)
  if err then
    vim.notify('save_vo() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then
    vim.notify('save_vo() failed:', vim.log.levels.ERROR)
    vim.print(request_result.err)
  end
end


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
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = self.ag,
    buffer = bufnr,
    desc = "Request proof/goals on cursor movement",
    callback = function() self:goals_async_debounced() end,
  })
  -- nvim bug? If the current coq buf is the only valid buffer and I bwipeout
  -- that buffer, this buffer is newly added to buffer list.
  vim.api.nvim_create_autocmd({"BufDelete", "LspDetach"}, {
    group = self.ag,
    buffer = bufnr,
    desc = "Unregister deleted/detached buffer",
    callback = function(ev) self:unregister(ev.buf) end,
  })
  self:goals_async(bufnr)
end

function CoqLSPNvim:dispose()
  self.debounce_timer:stop()
  self.debounce_timer:close()
  for bufnr, _ in pairs(self.buffers) do
    self:unregister(bufnr)
  end
  vim.api.nvim_clear_autocmds{ group = self.ag }
end

---@param user_on_attach? fun(client: lsp.Client, bufnr: buffer)
---@return fun(client: lsp.Client, bufnr: buffer)
local function make_on_attach(user_on_attach)
  return function(client, bufnr)
    if not the_client then
      the_client = CoqLSPNvim:new(client)
    elseif the_client.lc ~= client then
      error('coq-lsp client must be unique')
    end
    if not the_client.buffers[bufnr] then
      the_client:register(bufnr)
    end
    if user_on_attach then
      user_on_attach(client, bufnr)
    end
  end
end

local function make_on_exit(user_on_exit)
  return function(code, signal, client_id)
    if user_on_exit then
      user_on_exit(code, signal, client_id)
    end
    -- NOTE: on_exit runs in_fast_event
    vim.schedule(function()
      assert(the_client):dispose()
      the_client = nil
    end)
  end
end

---@param opts { coq_lsp_nvim?: table<string,any>, lsp?: table<string,any> }
local function setup(opts)
  opts = opts or {}
  opts.lsp = opts.lsp or {}
  opts.lsp.handlers = vim.tbl_extend('keep', opts.lsp.handlers or {}, {
    -- TODO: throttle fileProgress handling.. or maybe let the server do that
    ['$/coq/fileProgress'] = file_progress_handler,
  })
  local user_on_attach = opts.lsp.on_attach
  opts.lsp.on_attach = make_on_attach(user_on_attach)
  local user_on_exit = opts.lsp.on_exit
  opts.lsp.on_exit = make_on_exit(user_on_exit)
  require('lspconfig').coq_lsp.setup(opts.lsp)
end

return {
  client = function() return the_client end,
  get_document = function () assert(the_client):get_document() end,
  goals_async = function() assert(the_client):goals_async() end,
  goals_sync = function() assert(the_client):goals_sync() end,
  panels = function() assert(the_client):open_info_panel() end,
  save_vo = function() assert(the_client):save_vo() end,
  setup = setup,
}
