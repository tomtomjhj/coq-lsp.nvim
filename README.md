# setup
```vim
Plug 'neovim/nvim-lspconfig'
Plug 'tomtomjhj/coq-lsp.nvim'

...

lua require'coq-lsp'.setup()
```

# interface

Show goals at the cursor
```vim
:lua require'coq-lsp'.goals()
```
