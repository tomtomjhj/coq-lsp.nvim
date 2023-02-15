-- https://github.com/whonore/Coqtail/issues/7
-- https://github.com/ProofGeneral/PG/issues/619#issuecomment-1422540642
-- NOTE: coq-lsp sometimes DOSes client. Crashes vscode and breaks nvim rpc stuff.

local lspconfig = require('lspconfig')
local util = require('vim.lsp.util')

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
    local start_idx = util._get_line_byte_from_position(
      bufnr,
      { line = start_line, character = start_char },
      offset_encoding
    )
    local end_idx = util._get_line_byte_from_position(
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

-- main bufnr ↦ info panel bufnr
local info_panel = {}

local function create_info_panel(bufnr)
  local info_bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(info_bufnr, 'filetype', 'coq-goals')
  info_panel[bufnr] = info_bufnr
end

local function get_info_panel(bufnr)
  if info_panel[bufnr] then
    return info_panel[bufnr]
  end
  create_info_panel(bufnr)
  return info_panel[bufnr]
end

local function open_info_panel(bufnr)
  local win = vim.api.nvim_get_current_win()
  vim.cmd.sbuffer {
    args = { info_panel[bufnr] },
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

local goals_requests = {}

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
  vim.api.nvim_buf_set_lines(get_info_panel(bufnr), 0, -1, false, lines)
end

local function goals_async()
  local bufnr = vim.api.nvim_get_current_buf()
  local cancel_old = goals_requests[bufnr]
  if cancel_old then
    goals_requests[bufnr] = nil
    cancel_old()
  end
  local params = vim.lsp.util.make_position_params()
  local cancel = vim.lsp.buf_request_all(bufnr, 'proof/goals', params, function(results) show_goals(results[1].result) end)
  goals_requests[bufnr] = cancel
end

local function goals_sync()
  local params = vim.lsp.util.make_position_params()
  local results, err = vim.lsp.buf_request_sync(0, 'proof/goals', params, 500)
  if err then
    print('goals_sync() failed: ' .. err)
    return
  end
  show_goals(results[1].result)
end

local ag = vim.api.nvim_create_augroup("coq-lsp", { clear = true })

local function on_attach(client, bufnr)
  create_info_panel(bufnr)
  open_info_panel(bufnr)
  vim.api.nvim_create_autocmd({"CursorMoved", "CursorMovedI"}, {
    group = ag,
    buffer = bufnr,
    desc = "Request proof/goals on cursor movement",
    callback = goals_async,
  })
  goals_async()
end

local function setup(opts)
  opts = opts or {}
  opts.handlers = vim.tbl_extend('keep', opts.handlers or {}, {
    ['$/coq/fileProgress'] = file_progress_handler,
  })
  local user_on_attach = opts.on_attach
  opts.on_attach = function(client, bufnr)
    on_attach(client, bufnr)
    if user_on_attach then
      user_on_attach(client, bufnr)
    end
  end
  lspconfig.coq_lsp.setup(opts)
end

return {
  setup = setup,
  goals_sync = goals_sync,
  goals_async = goals_async,
  panels = function() open_info_panel(vim.api.nvim_get_current_buf()) end,
}
