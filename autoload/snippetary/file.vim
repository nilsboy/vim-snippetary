"" snippetary: snippet file discovery and loading.

let s:cache = {}

" Snippet directories: honors g:UltiSnipsSnippetDirectories for compatibility
" when g:snippetary_snippet_dirs is not set. Relative names search
" runtimepath; absolute paths are used directly.
func! snippetary#file#dirs() abort
    let dirs = get(g:, 'snippetary_snippet_dirs', 0)
    if type(dirs) != type([])
        let dirs = get(g:, 'UltiSnipsSnippetDirectories', ['UltiSnips'])
    endif
    let out = []
    for d in dirs
        if type(d) != type('')
            continue
        endif
        if d =~# '^[/~]' || (exists('+shellslash') && d =~# '^[A-Za-z]:')
            call add(out, expand(d))
        else
            call extend(out, split(globpath(&runtimepath, d), "\n"))
        endif
    endfor
    return out
endf

" All snippet files for one scope (ft.snippets, ft_*.snippets, ft/*.snippets).
func! snippetary#file#for_scope(scope) abort
    let out = []
    for d in snippetary#file#dirs()
        if !isdirectory(d)
            continue
        endif
        call extend(out, split(globpath(d, a:scope . '.snippets'), "\n"))
        call extend(out, split(globpath(d, a:scope . '_*.snippets'), "\n"))
        call extend(out, split(globpath(d, a:scope . '/*.snippets'), "\n"))
    endfor
    return out
endf

" Parse a file (with mtime caching); returns the parse dict or empty on error.
func! snippetary#file#read(path) abort
    let mtime = getftime(a:path)
    if mtime < 0
        return {}
    endif
    if has_key(s:cache, a:path) && s:cache[a:path].mtime == mtime
        return s:cache[a:path].info
    endif
    let lines = readfile(a:path)
    let info = snippetary#parse#snippets_file(lines)
    if len(info.errors)
        for msg in info.errors
            echohl WarningMsg
            echom 'snippetary: ' . a:path . ': ' . msg
            echohl None
        endfor
    endif
    if info.python && len(info.snips)
        echohl WarningMsg
        echom 'snippetary: ' . a:path
                    \ . ': python globals/interpolations are skipped'
        echohl None
    endif
    let s:cache[a:path] = {'mtime': mtime, 'info': info}
    return info
endf

func! snippetary#file#clear_cache() abort
    let s:cache = {}
endf