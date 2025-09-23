# coq-lsp.nvim
A simple Neovim client for [`coq-lsp`](https://github.com/ejgallego/coq-lsp/).

## Prerequisites
* [Latest stable version of Neovim](https://github.com/neovim/neovim/releases/tag/stable)
* [`coq-lsp`](https://github.com/ejgallego/coq-lsp/#%EF%B8%8F-installation)

## Setup
```vim
Plug 'neovim/nvim-lspconfig' " only on neovim < 0.11
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
* coq-lsp.nvim uses Neovim's built-in LSP client and nvim-lspconfig.
  See [kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim/)
  for basic example configurations for working with LSP.
* On cursor movement, it asynchronously displays the goals for the position of cursor on the auxiliary panel.
* `:CoqLsp` command
    * `:CoqLsp open_info_panel`: Open the info panel for the current buffer.
    * `:CoqLsp saveVo`: Save the `.vo` file for the current buffer.
* [Commands from nvim-lspconfig](https://github.com/neovim/nvim-lspconfig#commands)
  work as expected.
  For example, run `:LspRestart` to restart `coq-lsp`.

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

NOTE:
Do not call `lspconfig.coq_lsp.setup()` or `vim.lsp.enable()` yourself.
`require'coq-lsp'.setup` does it for you.

## Features not implemented yet
* Fancy proofview rendering

## See also
* [coq.ctags](https://github.com/tomtomjhj/coq.ctags) for go-to-definition.
* [vscoq.nvim](https://github.com/tomtomjhj/vscoq.nvim) for `vscoqtop` client.
