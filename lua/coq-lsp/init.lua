---@type table<buffer, { info_bufnr: buffer, cancel_goals: fun() }>
local buffers = {}

local progress_ns = vim.api.nvim_create_namespace('coq-progress')

local CoqFileProgressKind = {
  Processing = 1,
  FatalError = 2
}

local function file_progress_handler(_, result, ctx, _)
  local bufnr = vim.uri_to_bufnr(result.textDocument.uri)
  local client = vim.lsp.get_client_by_id(ctx.client_id)

  -- TODO: Highlight is very noisy when typing. Use sign or something else.
  local offset_encoding = client.offset_encoding
  vim.api.nvim_buf_clear_namespace(bufnr, progress_ns, 0, -1)
  for _, info in ipairs(result.processing) do
    -- taken from vim.lsp.util.buf_highlight_references()
    local start_line, start_char = info.range['start']['line'], info.range['start']['character']
    local end_line, end_char = info.range['end']['line'], info.range['end']['character']
    local start_idx = vim.lsp.util._get_line_byte_from_position(
      bufnr,
      { line = start_line, character = start_char },
      offset_encoding
    )
    local end_idx = vim.lsp.util._get_line_byte_from_position(
      bufnr,
      { line = start_line, character = end_char },
      offset_encoding
    )
    local progress_highlight_kind = {
      [CoqFileProgressKind.Processing] = 'CoqtailSent',
      [CoqFileProgressKind.FatalError] = 'Error',
    }
    local kind = info.kind or CoqFileProgressKind.Processing
    vim.highlight.range(
      bufnr,
      progress_ns,
      progress_highlight_kind[kind],
      { start_line, start_idx },
      { end_line, end_idx },
      { priority = vim.highlight.priorities.user }
    )
  end
end

local function create_info_panel(bufnr)
  local info_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(info_bufnr, 'filetype', 'coq-goals')
  buffers[bufnr].info_bufnr = info_bufnr
end

local function get_info_bufnr(bufnr)
  local info_bufnr = buffers[bufnr].info_bufnr
  if info_bufnr and vim.api.nvim_buf_is_valid(info_bufnr) then
    return info_bufnr
  end
  create_info_panel(bufnr)
  return buffers[bufnr].info_bufnr
end

local function open_info_panel(bufnr)
  local win = vim.api.nvim_get_current_win()
  vim.cmd.sbuffer {
    args = { get_info_bufnr(bufnr) },
    mods = { keepjumps = true, keepalt = true, vertical = true, split = 'belowright'},
  }
  vim.cmd.clearjumps()
  vim.api.nvim_set_current_win(win)
end

-- TODO: Render goals nicely.
-- see also lean.nvim infoview stuff
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

-- answer: GoalAnswer
local function show_goals(answer)
  local bufnr = vim.uri_to_bufnr(answer.textDocument.uri)
  local goal_config = answer.goals or {}
  local goals = goal_config.goals or {}
  local rendered = {}
  for i, goal in ipairs(goals) do
    rendered[#rendered+1] = render_goal(i, #goals, goal)
  end
  local lines = {}
  -- TODO: convert to byte index?
  lines[#lines+1] = vim.fn.bufname(bufnr) .. ':' .. (answer.position.line + 1) .. ':' .. (answer.position.character + 1)
  -- NOTE: each Pp can contain newline, which isn't allowed by nvim_buf_set_lines
  vim.list_extend(lines, vim.split(table.concat(rendered, '\n\n\n────────────────────────────────────────────────────────────\n'), '\n'))
  vim.api.nvim_buf_set_lines(get_info_bufnr(bufnr), 0, -1, false, lines)
end

local function goals_async()
  local bufnr = vim.api.nvim_get_current_buf()
  local cancel_old = buffers[bufnr].cancel_goals
  if cancel_old then
    buffers[bufnr].cancel_goals = nil
    cancel_old()
  end
  local params = vim.lsp.util.make_position_params()
  local cancel = vim.lsp.buf_request_all(bufnr, 'proof/goals', params, function(results)
    -- results: client_id ↦ { result: GoalAnswer, error: { code, message, data? } }
    buffers[bufnr].cancel_goals = nil
    for _, request_result in pairs(results) do
      if request_result.error then return end
      show_goals(request_result.result)
    end
  end)
  buffers[bufnr].cancel_goals = cancel
end

local function goals_sync()
  local params = vim.lsp.util.make_position_params()
  local results, err = vim.lsp.buf_request_sync(0, 'proof/goals', params, 500)
  if err then
    print('goals_sync() failed: ' .. err)
    return
  end
  assert(results ~= nil)
  for _, request_result in pairs(results) do
    if request_result.err then return end
    show_goals(request_result.result)
  end
end

local ag = vim.api.nvim_create_augroup("coq-lsp", { clear = true })

local function unregister(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, progress_ns, 0, -1)
  if buffers[bufnr].info_bufnr then
    vim.api.nvim_buf_delete(buffers[bufnr].info_bufnr, { force = true })
  end
  buffers[bufnr] = nil
end

local function register(bufnr)
  assert(buffers[bufnr] == nil)
  buffers[bufnr] = {}
  create_info_panel(bufnr)
  open_info_panel(bufnr)
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = ag,
    buffer = bufnr,
    desc = "Request proof/goals on cursor movement",
    callback = goals_async,
  })
  vim.api.nvim_create_autocmd({"BufDelete"}, {
    group = ag,
    buffer = bufnr,
    desc = "Unregister deleted buffer",
    callback = function()
      unregister(bufnr)
    end,
  })
  goals_async()
end

local function stop()
  for _, client in ipairs(vim.lsp.get_active_clients{ name = 'coq_lsp' }) do
    client.stop(true)
  end
  for bufnr, _ in pairs(buffers) do
    unregister(bufnr)
  end
  vim.api.nvim_clear_autocmds{ group = ag }
end

local function setup(opts)
  opts = opts or {}
  opts.handlers = vim.tbl_extend('keep', opts.handlers or {}, {
    ['$/coq/fileProgress'] = file_progress_handler,
  })
  local user_on_attach = opts.on_attach
  opts.on_attach = function(client, bufnr)
    register(bufnr)
    if user_on_attach then
      user_on_attach(client, bufnr)
    end
  end
  require('lspconfig').coq_lsp.setup(opts)
end

local function status()
  vim.pretty_print(buffers)
end

return {
  setup = setup,
  goals_sync = goals_sync,
  goals_async = goals_async,
  panels = function() open_info_panel(vim.api.nvim_get_current_buf()) end,
  stop = stop,
  status = status,
}
