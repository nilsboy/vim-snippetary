"" snippetary: a pure-vimscript snippet engine that reads UltiSnips snippet
"" files. See doc/snippetary.txt.

if exists('g:loaded_snippetary') || &cp
    finish
endif
let g:loaded_snippetary = 1
let g:snippetary_version = '1.0.2'

let s:save_cpo = &cpo
set cpo&vim

if !exists('g:snippetary_snippet_dirs') && exists('g:UltiSnipsSnippetDirectories')
    let g:snippetary_snippet_dirs = g:UltiSnipsSnippetDirectories
endif

if !exists('g:snippetary_expand_trigger')
    let g:snippetary_expand_trigger = '<tab>'
endif
if !exists('g:snippetary_jump_backward_trigger')
    let g:snippetary_jump_backward_trigger = '<s-tab>'
endif

" =============== plug maps ===============

inoremap <silent> <Plug>(snippetary-next-or-trigger)
            \ <C-R>=snippetary#NextOrTrigger()<CR>
snoremap <silent> <Plug>(snippetary-next-or-trigger)
            \ <Esc>a<C-R>=snippetary#NextOrTrigger()<CR>
inoremap <silent> <Plug>(snippetary-back)
            \ <C-R>=snippetary#BackwardsSnippet()<CR>
snoremap <silent> <Plug>(snippetary-back)
            \ <Esc>a<C-R>=snippetary#BackwardsSnippet()<CR>
xnoremap <silent> <Plug>(snippetary-visual)
            \ :<C-u>call snippetary#GrabVisual()<CR>gv"_c

execute 'imap <silent>' g:snippetary_expand_trigger
            \ '<Plug>(snippetary-next-or-trigger)'
execute 'smap' g:snippetary_expand_trigger
            \ '<Plug>(snippetary-next-or-trigger)'
execute 'imap <silent>' g:snippetary_jump_backward_trigger
            \ '<Plug>(snippetary-back)'
execute 'smap' g:snippetary_jump_backward_trigger
            \ '<Plug>(snippetary-back)'
execute 'xmap' g:snippetary_expand_trigger
            \ '<Plug>(snippetary-visual)'

" =============== commands ===============

command! -nargs=0 SnippetaryReload call snippetary#reload()
command! -nargs=0 SnippetaryClean call snippetary#clean_current_buffer()
command! -nargs=0 SnippetaryVersion
            \ echo 'snippetary version ' . g:snippetary_version

" =============== autocommands ===============

augroup snippetary
    autocmd!
    autocmd BufWinEnter,FileType * call snippetary#load_buffer()
    autocmd CursorMoved,CursorMovedI * call snippetary#cursor_update()
    autocmd BufUnload *
                \ if exists('b:snippetary') | unlet b:snippetary | endif
augroup END

" Basic settings for editing snippet files themselves.
autocmd snippetary BufRead,BufNewFile *.snippets,*.snippet
            \ setlocal filetype=snippets

let &cpo = s:save_cpo