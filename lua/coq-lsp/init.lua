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
---@type lsp.Client?
local the_client

---@type table<buffer, { info_bufnr: buffer, cancel_goals?: fun(), debounce_timer: uv_timer_t }>
local buffers = {}

---@class CoqLSPNvimConfig
---@field show_goals_on "manual"|"cursor"
local config = {
  -- TODO: implement it; should be dynamically configurable
  show_goals_on = "cursor",
  goals_debounce = 150,
}

local progress_ns = vim.api.nvim_create_namespace('coq-progress')

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
  vim.api.nvim_buf_clear_namespace(bufnr, progress_ns, 0, -1)
  -- TODO: Highlight is very noisy when typing. Use sign or something else.
  for _, info in ipairs(result.processing) do
    local kind = info.kind or CoqFileProgressKind.Processing
    vim.highlight.range(
      bufnr,
      progress_ns,
      progress_highlight_kind[kind],
      position_lsp_to_api(bufnr, info.range['start'], the_client.offset_encoding),
      position_lsp_to_api(bufnr, info.range['end'], the_client.offset_encoding),
      { priority = vim.highlight.priorities.user }
    )
  end
end

---@param bufnr buffer
local function create_info_panel(bufnr)
  local info_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(info_bufnr, 'filetype', 'coq-goals')
  buffers[bufnr].info_bufnr = info_bufnr
end

---@param bufnr buffer
local function get_info_bufnr(bufnr)
  local info_bufnr = buffers[bufnr].info_bufnr
  if info_bufnr and vim.api.nvim_buf_is_valid(info_bufnr) then
    return info_bufnr
  end
  create_info_panel(bufnr)
  return buffers[bufnr].info_bufnr
end

---@param bufnr? buffer
local function open_info_panel(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  vim.cmd.sbuffer {
    args = { get_info_bufnr(bufnr) },
    mods = { keepjumps = true, keepalt = true, vertical = true, split = 'belowright'},
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
local function show_goals(answer, position)
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
  vim.list_extend(lines, vim.split(table.concat(rendered, '\n\n\n????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????\n'), '\n'))
  vim.api.nvim_buf_set_lines(get_info_bufnr(bufnr), 0, -1, false, lines)
end

---@param bufnr? buffer
---@param position? MarkPosition
local function goals_async(bufnr, position)
  assert(the_client)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  position = position or guess_position(bufnr)
  local cancel_old = buffers[bufnr].cancel_goals
  if cancel_old then
    buffers[bufnr].cancel_goals = nil
    cancel_old()
  end
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = make_position_params(bufnr, position, the_client.offset_encoding)
  }
  local cancel = request_async(the_client, bufnr, 'proof/goals', params, function(err, result)
    buffers[bufnr].cancel_goals = nil
    if err then return end
    show_goals(result, position)
  end)
  buffers[bufnr].cancel_goals = cancel
end

---@param bufnr buffer
---@param position? MarkPosition
local function goals_async_debounced(bufnr, position)
  -- Must get the position before scheduling, because at the time of execution,
  -- the current window may have changed.
  position = position or guess_position(bufnr)
  local timer = buffers[bufnr].debounce_timer
  -- NOTE: Stopping the timer doesn't touch already scheduled callbacks.
  timer:stop()
  timer:start(
    config.goals_debounce,
    0,
    vim.schedule_wrap(function() goals_async(bufnr, position) end)
  )
end

---@param bufnr? buffer
---@param position? MarkPosition
local function goals_sync(bufnr, position)
  assert(the_client)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  position = position or guess_position(bufnr)
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
    position = make_position_params(bufnr, position, the_client.offset_encoding)
  }
  local request_result, err = the_client.request_sync('proof/goals', params, 500, bufnr)
  if err then
    vim.notify('goals_sync() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then return end
  show_goals(request_result.result, position)
end


---@param bufnr? buffer
local function get_document(bufnr)
  assert(the_client)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }
  local request_result, err = the_client.request_sync('coq/getDocument', params, 500, bufnr)
  if err then
    vim.notify('get_document() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then return end
  return request_result.result
end


---@param bufnr? buffer
local function save_vo(bufnr)
  assert(the_client)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }
  local request_result, err = the_client.request_sync('coq/saveVo', params, 500, bufnr)
  if err then
    vim.notify('save_vo() failed: ' .. err, vim.log.levels.ERROR)
    return
  end
  assert(request_result)
  if request_result.err then
    vim.notify('save_vo() failed:', vim.log.levels.ERROR)
    vim.pretty_print(request_result.err)
  end
end


local ag = vim.api.nvim_create_augroup("coq-lsp", { clear = true })

---@param bufnr buffer
local function unregister(bufnr)
  assert(buffers[bufnr])
  vim.api.nvim_buf_clear_namespace(bufnr, progress_ns, 0, -1)
  vim.api.nvim_clear_autocmds { group = ag, buffer = bufnr }
  buffers[bufnr].debounce_timer:stop()
  buffers[bufnr].debounce_timer:close()
  if buffers[bufnr].info_bufnr then
    vim.api.nvim_buf_delete(buffers[bufnr].info_bufnr, { force = true })
  end
  buffers[bufnr] = nil
end

---@param bufnr buffer
local function register(bufnr)
  assert(buffers[bufnr] == nil)
  buffers[bufnr] = {}
  create_info_panel(bufnr)
  open_info_panel(bufnr)
  buffers[bufnr].debounce_timer = assert(vim.loop.new_timer(), 'Could not create timer')
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = ag,
    buffer = bufnr,
    desc = "Request proof/goals on cursor movement",
    callback = function(ev) goals_async_debounced(ev.buf) end,
  })
  -- nvim bug? If the current coq buf is the only valid buffer and I bwipeout
  -- that buffer, this buffer is newly added to buffer list.
  vim.api.nvim_create_autocmd({"BufDelete", "LspDetach"}, {
    group = ag,
    buffer = bufnr,
    desc = "Unregister deleted/detached buffer",
    callback = function(ev) unregister(ev.buf) end,
  })
  goals_async(bufnr)
end

local function stop()
  assert(the_client)
  -- TODO: maybe no need to force after https://github.com/ejgallego/coq-lsp/pull/375
  the_client.stop(true)
  the_client = nil
  for bufnr, _ in pairs(buffers) do
    unregister(bufnr)
  end
  vim.api.nvim_clear_autocmds{ group = ag }
end

---@param user_on_attach? fun(client: lsp.Client, bufnr: buffer)
---@return fun(client: lsp.Client, bufnr: buffer)
local function make_on_attach(user_on_attach)
  return function(client, bufnr)
    if not the_client then
      the_client = client
    elseif the_client ~= client then
      error('coq-lsp client must be unique')
    end
    if not buffers[bufnr] then
      register(bufnr)
    end
    if user_on_attach then
      user_on_attach(client, bufnr)
    end
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
  require('lspconfig').coq_lsp.setup(opts.lsp)
end

local function status()
  vim.pretty_print('client', the_client)
  vim.pretty_print('config', config)
  vim.pretty_print('buffers', buffers)
end

return {
  get_document = get_document,
  goals_async = goals_async,
  goals_sync = goals_sync,
  panels = open_info_panel,
  save_vo = save_vo,
  setup = setup,
  status = status,
  stop = stop,
}
