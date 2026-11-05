" test-config: throwaway nvim config for manually testing snippetary.
" Start it with:
"   nvim -u test-config/init.vim test-config/demo.txt
" Snipppets live in test-config/snippets/_.snippets and apply to every
" filetype. `<tab>` expands, `<s-tab>` jumps backwards.

set nocompatible
set number
set backspace=indent,eol,start
set noswapfile
syntax enable

" keep user pack plugins from intercepting the fresh plugin
set packpath=

let s:root = expand('<script>:p:h:h')
execute 'set runtimepath^=' . s:root

filetype plugin indent on

" belt and suspenders: the startup phase sources plugin/snippetary.vim
" from the runtimepath above; this makes it work even when the config is
" sourced manually after startup.
runtime plugin/snippetary.vim

let g:snippetary_snippet_dirs = [s:root . '/test-config/snippets']