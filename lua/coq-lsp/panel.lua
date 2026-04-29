-- Info-panel window and info-buffer management.

local M = {}

---@type table<integer, window> tabpage -> info panel window
local panel_wins = {}
---@type table<buffer, buffer> coq bufnr -> info bufnr
local info_bufnrs = {}

---@param bufnr buffer coq buffer
---@return buffer info bufnr (created lazily)
function M.get_info_bufnr(bufnr)
  local info = info_bufnrs[bufnr]
  if info and vim.api.nvim_buf_is_valid(info) then
    return info
  end
  info = vim.api.nvim_create_buf(false, true)
  vim.bo[info].filetype = 'coq-goals'
  info_bufnrs[bufnr] = info
  return info
end

---@param bufnr buffer coq buffer
---@param lines string[]
function M.render(bufnr, lines)
  local info_bufnr = M.get_info_bufnr(bufnr)
  local views = {} ---@type table<window, vim.fn.winsaveview.ret>
  for _, win in ipairs(vim.fn.win_findbuf(info_bufnr) or {}) do
    vim.api.nvim_win_call(win, function()
      views[win] = vim.fn.winsaveview()
    end)
  end
  vim.api.nvim_buf_set_lines(info_bufnr, 0, -1, false, lines)
  for win, view in pairs(views) do
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview(view)
    end)
  end
end

---Open (or retarget) the info panel in the current tab to show `bufnr`'s goals.
---If the current tab already has a panel, retarget it without creating a new split.
---@param bufnr? buffer coq buffer (defaults to current)
function M.open(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local info_bufnr = M.get_info_bufnr(bufnr)
  local tab = vim.api.nvim_get_current_tabpage()

  local existing = panel_wins[tab]
  if existing and vim.api.nvim_win_is_valid(existing) then
    vim.api.nvim_win_set_buf(existing, info_bufnr)
    return
  end

  local cur_win = vim.api.nvim_get_current_win()
  vim.cmd.sbuffer {
    args = { info_bufnr },
    -- TODO: customization
    -- See `:h nvim_parse_cmd`. Note that the "split size" is `range`.
    mods = { keepjumps = true, keepalt = true, vertical = true, split = 'belowright' },
  }
  vim.cmd.clearjumps()
  panel_wins[tab] = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(cur_win)
end

---Retarget the current tab's panel (if any) to `bufnr`'s info buffer.
---No-op if there is no panel in this tab (respects manual close).
---@param bufnr buffer coq buffer
function M.retarget(bufnr)
  local tab = vim.api.nvim_get_current_tabpage()
  local win = panel_wins[tab]
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_win_set_buf(win, M.get_info_bufnr(bufnr))
end

local ag = vim.api.nvim_create_augroup('coq-lsp-panel', { clear = true })

vim.api.nvim_create_autocmd('WinClosed', {
  group = ag,
  desc = 'Forget closed coq-lsp info panel windows',
  callback = function(ev)
    local closed = tonumber(ev.match)
    for tab, win in pairs(panel_wins) do
      if win == closed then
        panel_wins[tab] = nil
      end
    end
  end,
})

vim.api.nvim_create_autocmd('BufDelete', {
  group = ag,
  desc = 'Clean up info buffer when its coq buffer is deleted',
  callback = function(ev)
    local info = info_bufnrs[ev.buf]
    if info then
      info_bufnrs[ev.buf] = nil
      if vim.api.nvim_buf_is_valid(info) then
        vim.api.nvim_buf_delete(info, { force = true })
      end
    end
  end,
})

return M
