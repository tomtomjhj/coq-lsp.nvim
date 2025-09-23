local M = {}

---@class coqlsp.config
---@field goals_debounce integer
---@field show_goals_on "manual"|"cursor"

---@type coqlsp.config
local default_config = {
  -- TODO: implement it; should be dynamically configurable
  show_goals_on = 'cursor',
  goals_debounce = 150,
  -- TODO: info panel mode: global panel or one for each buffer
}

---@type table<integer, CoqLSPNvim>
M.clients = {}

local function make_on_init(user_on_init)
  return function(client, initialize_result)
    local ok, CoqLSPNvim = pcall(require, 'coq-lsp.client')
    if not ok then
      vim.print('[coq-lsp.nvim] on_init failed', CoqLSPNvim)
      return
    end
    M.clients[client.id] = CoqLSPNvim:new(client, default_config)
    if user_on_init then
      user_on_init(client, initialize_result)
    end
  end
end

---@param user_on_attach? fun(client: lsp.Client, bufnr: buffer)
---@return fun(client: lsp.Client, bufnr: buffer)
local function make_on_attach(user_on_attach)
  return function(client, bufnr)
    if not M.clients[client.id].buffers[bufnr] then
      M.clients[client.id]:register(bufnr)
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
      M.clients[client_id]:dispose()
      M.clients[client_id] = nil
    end)
  end
end

---@type lsp.Handler
local function fileProgress_notification_handler(_, result, ctx, _)
  M.clients[ctx.client_id]:fileProgress(result)
end

---@param opts { coq_lsp_nvim?: table<string,any>, lsp?: table<string,any> }
function M.setup(opts)
  opts = opts or {}
  opts.lsp = opts.lsp or {}
  opts.lsp.handlers = vim.tbl_extend('keep', opts.lsp.handlers or {}, {
    ['$/coq/fileProgress'] = fileProgress_notification_handler,
  })
  local user_on_init = opts.lsp.on_init
  opts.lsp.on_init = make_on_init(user_on_init)
  local user_on_attach = opts.lsp.on_attach
  opts.lsp.on_attach = make_on_attach(user_on_attach)
  local user_on_exit = opts.lsp.on_exit
  opts.lsp.on_exit = make_on_exit(user_on_exit)

  if vim.fn.has('nvim-0.11') == 1 then
    -- Use native LSP setup for Neovim 0.11+
    local config = {
        cmd = { 'coq-lsp' },
        filetypes = { 'coq' },
        root_markers = { '_CoqProject', '.git' },
    }

    vim.lsp.config('coq_lsp', vim.tbl_deep_extend('force', config, opts.lsp))
    vim.lsp.enable('coq_lsp')
  else
    -- Fallback to lspconfig for older versions
    require('lspconfig').coq_lsp.setup(opts.lsp)
  end
end

return M
