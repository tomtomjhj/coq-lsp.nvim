# coq-lsp.nvim
A simple Neovim client for [`coq-lsp`](https://github.com/ejgallego/coq-lsp/).

## Prerequisites
* [Latest stable version of Neovim](https://github.com/neovim/neovim/releases/tag/stable)
* [`coq-lsp`](https://github.com/ejgallego/coq-lsp/#%EF%B8%8F-installation)

## Setup
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'whonore/Coqtail' " for ftdetect, syntax, basic ftplugin, etc
Plug 'tomtomjhj/coq-lsp.nvim'

...

" Don't load Coqtail
let g:loaded_coqtail = 1
let g:coqtail#supported = 0

" Setup coq-lsp.nvim
lua require'coq-lsp'.setup()
```

## Interface
coq-lsp.nvim uses Neovim's built-in LSP client.
See [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim/) or
[lsp-zero.nvim](https://github.com/VonHeikemen/lsp-zero.nvim)
for example configurations.

ATM, this plugin does not create any Ex-commands or mappings.

On cursor movement, it asynchronously displays the goals for the position of cursor on the auxiliary panel.

Open auxiliary panels for the current buffer:
```vim
:lua require'coq-lsp'.panels()
```

Stop `coq-lsp`:
```vim
:lua require'coq-lsp'.stop()
```
Do not use lspconfig's `:LspStop` and `:LspRestart`.

## Configurations

```lua
require'coq-lsp'.setup {
  -- The configuration for coq-lsp.nvim.
  -- The following is the default configuration.
  coq_lsp_nvim = {
    -- to be added
  },

  -- The configuration forwarded to `:help lspconfig-setup`.
  -- The following is an example.
  lsp = {
    on_attach = function(client, bufnr)
      -- your mappings, etc
    end,
    -- coq-lsp server initialization configurations, defined here:
    -- https://github.com/ejgallego/coq-lsp/blob/main/editor/code/src/config.ts#L3
    -- Documentations are at https://github.com/ejgallego/coq-lsp/blob/main/editor/code/package.json.
    init_options = {
      show_notices_as_diagnostics = true,
    },
    autostart = false, -- use this if you want to manually launch coq-lsp with :LspStart.
  },
}
```
