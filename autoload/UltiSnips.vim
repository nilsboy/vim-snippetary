"" UltiSnips-API shims backed by snippetary. Lets coc-ultisnips (and other
"" tooling built on the UltiSnips# interface) use snippetary as the engine.
"" Only relevant while the real UltiSnips is not loaded: drop this file
"" alongside re-enabling SirVer/ultisnips (its own autoload takes over).

func! UltiSnips#SnippetsInCurrentScope(...) abort
    call snippetary#load_buffer()
    let st = snippetary#session()
    " list of {key, description}, alphabetical; a list keeps its order in
    " the coc popup (a dict from vimscript reaches javascript in hash
    " bucket order, so the extension's Object.keys() iteration is unsorted)
    let out = []
    for l:trig in keys(st.snips)
        call add(out, {'key': l:trig, 'description': st.snips[l:trig][0].desc})
    endfor
    return sort(out, {a, b -> toupper(a.key) ># toupper(b.key) ? 1 :
                \ (toupper(a.key) <# toupper(b.key) ? -1 : 0)})
endfunc

func! UltiSnips#ExpandSnippet() abort
    call feedkeys("\<Plug>(snippetary-next-or-trigger)", 'm')
endfunc
