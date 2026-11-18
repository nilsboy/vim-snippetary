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
" The all-filetypes scope '_' additionally honors the legacy all.snippets
" naming (and its all_*/all/ variants); duplicates from overlapping globs
" (e.g. _*.snippets also matching _.snippets) are removed.
func! snippetary#file#for_scope(scope) abort
    let out = []
    let pats = [a:scope . '.snippets', a:scope . '_*.snippets',
                \ a:scope . '/*.snippets']
    if a:scope ==# '_'
        call extend(pats, ['all.snippets', 'all_*.snippets', 'all/*.snippets'])
    endif
    for d in snippetary#file#dirs()
        if !isdirectory(d)
            continue
        endif
        for p in pats
            call extend(out, split(globpath(d, p), "\n"))
        endfor
    endfor
    let uniq = []
    let seen = {}
    for f in out
        if !has_key(seen, f)
            call add(uniq, f)
            let seen[f] = 1
        endif
    endfor
    return uniq
endf

" Path to open when editing a snippet file for one scope: the first existing
" file found, else the file to create in the first configured directory (for
" relative directory names that resolve nowhere, the first runtimepath
" entry is used as the base).
func! snippetary#file#edit_target(scope) abort
    let existing = snippetary#file#for_scope(a:scope)
    if len(existing)
        return existing[0]
    endif
    return snippetary#file#fallback_dir() . '/' . a:scope . '.snippets'
endf

" First configured snippet dir, resolved even when it does not exist.
func! snippetary#file#fallback_dir() abort
    let names = get(g:, 'snippetary_snippet_dirs',
                \ get(g:, 'UltiSnipsSnippetDirectories', ['UltiSnips']))
    for name in names
        if type(name) != type('') || name ==# ''
            continue
        endif
        if name =~# '^[/~]' || (exists('+shellslash') && name =~# '^[A-Za-z]:')
            return expand(name)
        endif
        let resolved = split(globpath(&runtimepath, name), "\n")
        if len(resolved)
            return resolved[0]
        endif
        return expand(get(split(&runtimepath, ','), 0, '.')) . '/' . name
    endfor
    return expand(get(split(&runtimepath, ','), 0, '.')) . '/UltiSnips'
endf

" Edit a file and place the cursor on one of its lines (1-based).
func! snippetary#file#open_at(path, line) abort
    execute 'edit ' . fnameescape(a:path)
    if a:line > 0
        call cursor(a:line, 1)
    endif
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
    let s:cache[a:path] = {'mtime': mtime, 'info': info}
    return info
endf

func! snippetary#file#clear_cache() abort
    let s:cache = {}
endf