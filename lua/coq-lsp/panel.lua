-- Info-panel window and info-buffer management.
--
-- A panel is a UI artifact tied to a coq buffer, not to an LSP client.
--
-- `panels` is keyed by an opaque "panel key" chosen by the caller —
-- typically a tabpage id (one panel per tab) or a coq bufnr (one panel per
-- buffer). The panel module doesn't care which; it just maps key -> window.

local M = {}

---@alias coqlsp.PanelKey integer

-- winid = open, false = dismissed, absent = never opened.
---@type table<coqlsp.PanelKey, window|false>
local panels = {}
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

---Open (or retarget) the info panel for `key` to show `bufnr`'s goals.
---If the key already has a valid panel window, retarget it without creating a new split.
---@param key coqlsp.PanelKey caller-chosen scope (tabpage id or bufnr)
---@param bufnr buffer coq buffer
function M.open(key, bufnr)
  local info_bufnr = M.get_info_bufnr(bufnr)

  local existing = panels[key]
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
  panels[key] = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(cur_win)
end

---Like `open`, but respects a prior manual close.
---@param key coqlsp.PanelKey
---@param bufnr buffer coq buffer
function M.ensure_open(key, bufnr)
  if panels[key] ~= false then
    M.open(key, bufnr)
  end
end

---Retarget `key`'s panel (if any) to `bufnr`'s info buffer.
---No-op if the key has no valid panel (respects manual close).
---@param key coqlsp.PanelKey
---@param bufnr buffer coq buffer
function M.retarget(key, bufnr)
  local win = panels[key]
  if not (win and vim.api.nvim_win_is_valid(win)) then
    return
  end
  vim.api.nvim_win_set_buf(win, M.get_info_bufnr(bufnr))
end

local ag = vim.api.nvim_create_augroup('coq-lsp-panel', { clear = true })

vim.api.nvim_create_autocmd('WinClosed', {
  group = ag,
  desc = 'Mark coq-lsp info panel as dismissed when closed',
  callback = function(ev)
    local closed = tonumber(ev.match)
    for key, win in pairs(panels) do
      if win == closed then
        panels[key] = false
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
    -- Clear last: nvim_buf_delete may fire WinClosed and re-set panels[ev.buf].
    panels[ev.buf] = nil
  end,
})

return M
