# setup
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

# interface
ATM, this plugin does not create any Ex-commands or mappings.

Show goals at the cursor
```vim
:lua require'coq-lsp'.goals()
```

Show auxiliary panels for the current buffer.
```vim
:lua require'coq-lsp'.panels()
```
