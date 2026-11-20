"" snippetary buffer engine: expansion, jumps, live mirror updates.
"
" After an expansion the buffer holds plain text and every tabstop / mirror
" is tracked as (line, byte-col) bookkeeping (the approach proven by
" snipMate). CursorMovedI deltas keep everything in sync while typing inside
" the current tabstop. No sentinel characters are inserted, so leaving a
" snippet through any path leaves clean text behind.

func! snippetary#session() abort
    if !exists('b:snippetary')
        let b:snippetary = {
                    \ 'snips': {}, 'ftdone': [], 'stack': [],
                    \ 'visual': '',
                    \ 'prev_l': 0, 'prev_d': 0}
    endif
    return b:snippetary
endf

func! snippetary#active() abort
    let st = snippetary#session()
    return empty(st.stack) ? {} : st.stack[-1]
endf

func! snippetary#scopes() abort
    " UltiSnips honors dotted filetypes; '_' holds snippets for every type.
    return split(&filetype, '\.') + ['_']
endf

" Load snippets for the current buffer (all scopes with extends chains).
func! snippetary#load_buffer() abort
    let st = snippetary#session()
    let todo = snippetary#scopes()
    while !empty(todo)
        let scope = remove(todo, 0)
        if index(st.ftdone, scope) >= 0
            continue
        endif
        for path in snippetary#file#for_scope(scope)
            call add(st.ftdone, scope)
            let info = snippetary#file#read(path)
            for ft in info.extends
                call add(todo, ft)
            endfor
            for snip in info.snips
                if !has_key(st.snips, snip.trig)
                    let st.snips[snip.trig] = []
                endif
                call add(st.snips[snip.trig], {
                            \ 'pri': snip.pri, 'desc': snip.desc,
                            \ 'opts': snip.opts, 'body': snip.body,
                            \ 'path': path, 'line': get(snip, 'head', 0)})
            endfor
        endfor
    endwhile
endf

" Force a reparse of all snippet files and reload this buffer.
func! snippetary#reload() abort
    call snippetary#file#clear_cache()
    for b in range(1, bufnr('$'))
        if buflisted(b) && bufexists(b)
            call setbufvar(b, 'snippetary', {'snips': {}, 'ftdone': [],
                        \ 'stack': [], 'visual': '',
                        \ 'prev_l': 0, 'prev_c': 0, 'prev_d': 0})
        endif
    endfor
    call snippetary#load_buffer()
endf

func! snippetary#clean_current_buffer() abort
    let st = snippetary#session()
    while !empty(st.stack)
        call remove(st.stack, -1)
    endwhile
endf

" =============== editing snippet files ===============

" The user-facing filetype scopes: the dotted pieces of &filetype (the
" engine-internal '_' all-filetypes scope is not part of this).
func! snippetary#user_scopes() abort
    return filter(copy(split(&filetype, '\.')), 'v:val !=# ""')
endf

" Open the snippet file for one scope; the file is created in the first
" configured snippet directory when it does not exist. An empty scope
" selects the first filetype scope (or the all-filetypes one).
func! snippetary#edit(scope) abort
    let scope = a:scope ==# '' ? get(snippetary#user_scopes(), 0, '_') : a:scope
    execute 'edit ' . fnameescape(snippetary#file#edit_target(scope))
endf

" Open the all-filetypes snippet file.
func! snippetary#edit_global() abort
    call snippetary#edit('_')
endf

" Jump to the file and header line of the snippet expanding around the
" cursor: the keyword under the cursor, else the last word behind the
" cursor position; falls back to the legacy before-cursor text probes and,
" on no match, to opening the buffer's filetype snippet file.
func! snippetary#goto_definition() abort
    let line = getline('.')
    let c = col('.')
    let word = ''
    if strpart(line, c - 1, 1) =~# '\k'
        " keyword run through the cursor char (stitched from both sides)
        let word = matchstr(strpart(line, 0, c - 1), '\k*$')
                    \ . matchstr(strpart(line, c - 1), '^\k*')
    endif
    if word ==# ''
        let word = snippetary#words_for_line(1, strpart(line, 0, c - 1))
    endif
    for before in [word, line[: col('.') - 1], line[: col('.') - 2]]
        let snip = snippetary#snip_at(before)[1]
        if !empty(snip) && get(snip, 'path', '') !=# ''
                    \ && get(snip, 'line', 0) > 0
            call snippetary#file#open_at(snip.path, snip.line)
            return
        endif
    endfor
    call snippetary#edit(get(snippetary#user_scopes(), 0, '_'))
endf

" =============== trigger matching ===============

func! snippetary#split_at_ws(text) abort
    return split(a:text, '\s\+', 1)
endf

" UltiSnips _words_for_line: the trailing num whitespace-token run of the
" text before the cursor, as its raw substring.
func! snippetary#words_for_line(num, before) abort
    let words = snippetary#split_at_ws(a:before)
    if len(words) <= a:num
        return substitute(a:before, '^\s\+\|\s\+$', '', 'g')
    endif
    let rest = a:before
    for i in range(len(words) - 1, len(words) - 1 - a:num, -1)
        if i < 0
            break
        endif
        let left = strridx(rest, words[i])
        let rest = rest[: left-1]
    endfor
    return substitute(strpart(a:before, len(rest)), '^\s\+\|\s\+$', '', 'g')
endf

func! snippetary#is_wordchar(c) abort
    return a:c ==# '' ? 0 : (a:c =~# '\k')
endf

" Boundary between the char before the trigger and the trigger's first char.
func! snippetary#word_boundary(left, first) abort
    if a:left ==# ''
        return 1
    endif
    return snippetary#is_wordchar(a:left) != snippetary#is_wordchar(a:first)
endf

" Text before the last n chars of "before" ('' when there is nothing left).
func! snippetary#leftchar(before, n) abort
    return len(a:before) <= a:n ? '' : a:before[: -a:n-1]
endf

" Find [trigger, snip, matched] for the text before the cursor.
func! snippetary#snip_at(before) abort
    let best = ['', {}, '', {}]
    for [trig, snips] in items(snippetary#session().snips)
        for snip in snips
            let o = snip.opts
            if stridx(o, 'e') >= 0
                continue
            endif
            let matched = ''
            let groups = {}
            if stridx(o, 'r') >= 0
                " UltiSnips _re_match: finditer over the text, fire on the
                " first match ending at the cursor; the matched span is
                " replaced and its capture groups feed the !v context
                let r = snippetary#re#matchend(
                            \ snippetary#re#program(trig), a:before)
                let matched = empty(r) ? '' : r.whole
                let groups = empty(r) ? {} : r.groups
            else
                " literal triggers: compare the trailing words of before
                let words = snippetary#words_for_line(
                            \ len(snippetary#split_at_ws(trig)), a:before)
                if stridx(o, 'i') >= 0
                    if words =~# '\V' . escape(trig, '\."') . '\$'
                        let matched = trig
                    endif
                elseif stridx(o, 'w') >= 0
                    if words ==# trig
                        let prefix = snippetary#leftchar(a:before,
                                    \ strlen(words))
                        if prefix ==# ''
                                    \ || snippetary#word_boundary(prefix[-1:],
                                    \ trig)
                            let matched = trig
                        endif
                    endif
                elseif words ==# trig
                    let matched = trig
                endif
            endif
            if matched !=# '' && stridx(o, 'b') >= 0
                " 'b': only whitespace may precede the matched text
                if substitute(snippetary#leftchar(a:before, strlen(matched)),
                            \ '[ \t]', '', 'g') !=# ''
                    let matched = ''
                endif
            endif
            if matched !=# ''
                        \ && (best[0] ==# '' || snip.pri > best[1].pri)
                let best = [trig, snip, matched, groups]
            endif
        endfor
    endfor
    return best
endf

" =============== expansion ===============

" n leading tabs -> indent string honoring setings (&et/&sw/&ts), the way
" UltiSnips ntabs_to_proper_indent does.
func! snippetary#tabs_to_indent(n) abort
    let spaces = repeat(' ', a:n * shiftwidth())
    let trailing = len(spaces) - strlen(substitute(spaces, ' *$', '', ''))
    let mid = strpart(spaces, 0, len(spaces) - trailing)
    if a:n == 0
        return ''
    endif
    if &expandtab
        return repeat(' ', len(mid)) . repeat(' ', trailing)
    endif
    return repeat("\t", len(mid) / &tabstop)
                \ . repeat(' ', len(mid) % &tabstop) . repeat(' ', trailing)
endf

" Prepare body lines the way UltiSnips launch() does: leading tabs of each
" line converted to proper indent; expansion indent prepended to all lines
" but the first; rstrip with the 'm' option; keep tabs with the 't' option.
func! snippetary#body_prep(body, indent, opts) abort
    let out = []
    let lines = split(a:body . "\n", "\n", 1)
    call remove(lines, -1)
    for i in range(len(lines))
        let line = lines[i]
        let nt = 0
        if stridx(a:opts, 't') < 0
            let nt = strlen(matchstr(line, '^\t*'))
        endif
        let pre = snippetary#tabs_to_indent(nt)
        if i != 0
            let pre = a:indent . pre
        endif
        let line = pre . strpart(line, nt)
        if stridx(a:opts, 'm') >= 0
            let line = substitute(line, '\s\+$', '', 'g')
        endif
        call add(out, line)
    endfor
    return out
endf

" Expansion handler (runs inside <C-R>= while in insert mode).
func! snippetary#do_expand(snip, matched, ...) abort
    let st = snippetary#session()
    let &undolevels = &undolevels
    let lnum = line('.')
    let c = col('.')
    let line = getline(lnum)
    let indent = matchstr(line, '^[ \t]*')
    let tlen = strlen(a:matched)
    let before = strpart(line, 0, c - 1 - tlen)
    let after = strpart(line, c - 1)

    " consume ${VISUAL} once, then stop tracking
    let vis = substitute(get(st, 'visual', ''), "\r", '', 'g')
    " expose the captured text to !v interpolations (SnBase64Visual et al)
    let b:snippetary_visual = vis
    " regex-group context for !v (the python match.group(n) analog);
    " literal snippets expose the trigger as the whole match
    let b:snippetary_match = extend({'0': a:matched},
                \ a:0 >= 1 ? a:1 : {})

    let tree = snippetary#parse#tokens(join(
                \ snippetary#body_prep(a:snip.body, indent, a:snip.opts), "\n"))
    let built = s:render(tree, a:snip, lnum, c, indent, st)
    let st.visual = ''
    let nl = built.lines
    if &foldenable
        silent! execute lnum . 'foldopen!'
    endif
    " splice the lines into the buffer
    if len(nl) == 1
        call setline(lnum, before . nl[0] . after)
    else
        call setline(lnum, before . nl[0])
        if len(nl) > 2
            call append(lnum, nl[1 : -2])
        endif
        " the last body line lands right below the second-to-last one; at
        " this point line('$') already contains the (len(nl) - 2) lines
        " appended above, so comparing against it moved this line one too
        " low whenever the buffer continued below the trigger
        call append(lnum + len(nl) - 2, nl[-1] . after)
    endif

    let exp = {'stops': built.stops, 'no': 0, 'opts': a:snip.opts}
    call s:abs_stops(exp, lnum, c, tlen)
    let exp.order = s:order_of(exp)
    if &foldenable
        silent! execute lnum . 'foldopen!'
    endif
    call add(st.stack, exp)
    let st.prev_l = line('.')
    let st.prev_d = col('$')
    return s:set_stop(exp, 0)
endf

" Sorted stop numbers; exiting stop 0 walks last; the last forward jump
" lands on 0 (the exit point) and ends the session.
" Render-relative (row, col) -> absolute buffer positions after the splice.
func! s:abs_stops(exp, lnum0, c0, tlen) abort
    let base = a:c0 - a:tlen
    for [n, stop] in items(a:exp.stops)
        let stop.l = a:lnum0 + stop.l
        let stop.c = stop.l == a:lnum0 ? base + stop.c - 1 : stop.c
        let stop.el = a:lnum0 + stop.el
        if stop.el == a:lnum0
            let stop.ec = base + stop.ec - 1
        endif
        for m in stop.mirrors
            let m.l = a:lnum0 + m.l
            let m.c = m.l == a:lnum0 ? base + m.c - 1 : m.c
            let m.el = a:lnum0 + m.el
            let m.ec = m.el == a:lnum0 ? base + m.ec - 1 : m.ec
        endfor
    endfor
endf

func! s:order_of(exp) abort
    let nums = sort(map(keys(a:exp.stops), 'str2nr(v:val)'), 'n')
    let noidx = index(nums, 0)
    if noidx >= 0
        call remove(nums, noidx)
    endif
    let a:exp.no = len(nums) > 0 ? nums[0] : 0
    return nums
endf

" =============== jumps ===============

func! snippetary#jump_keys(dir) abort
    let exp = snippetary#active()
    if empty(exp)
        return a:dir < 0 ? "\<s-tab>" : "\<tab>"
    endif
    return s:jump_stop(exp, a:dir < 0)
endf

" Next stop number in the walk, -1 when the session should end.
func! s:next_no(exp, backwards) abort
    let idx = index(a:exp.order, a:exp.no)
    if idx < 0
        return -1
    endif
    if a:backwards
        return idx == 0 ? -1 : a:exp.order[idx - 1]
    endif
    return idx == len(a:exp.order) - 1 ? -1 : a:exp.order[idx + 1]
endf

func! s:jump_stop(exp, backwards) abort
    " entering the exit stop 0 (backward walk wraps there) or running out of
    " stops both end the session
    call s:sync_stop(a:exp)
    let next = s:next_no(a:exp, a:backwards)
    if next == -1
        return s:end_session(a:exp)
    endif
    let a:exp.no = next
    return s:set_stop(a:exp, a:backwards)
endf

" The exit stop: place the cursor at its position and remove the session.
func! s:end_session(exp) abort
    let stop = a:exp.stops[0]
    call cursor(stop.l, stop.c)
    call s:remove_top_exp(a:exp)
    if stridx(a:exp.opts, 'x') >= 0
        return "\<esc>"
    endif
    return ''
endf

func! s:remove_top_exp(exp) abort
    call remove(snippetary#session().stack, -1)
endf

" Move to the stop set in exp.no: place cursor, return select-mode keys (or
" '' for empty stops, staying in insert).
func! s:set_stop(exp, backwards) abort
    let stop = a:exp.stops[a:exp.no]
    call cursor(stop.l, stop.c)
    let st = snippetary#session()
    let st.prev_l = line('.')
    let st.prev_d = col('$')
    return s:select_keys(stop)
endf

" Keys selecting the stop content in select mode; '' when the stop is empty.
func! s:select_keys(stop) abort
    if a:stop.l != a:stop.el
        return s:select_multiline(a:stop)
    endif
    let L = a:stop.ec - a:stop.c
    if L <= 0
        return ''
    endif
    let l = col('.') != 1 ? 'l' : ''
    if &sel ==# 'exclusive'
        return "\<esc>" . l . 'v' . L . "l\<c-g>"
    endif
    return L == 1 ? "\<esc>" . l . 'gh' : "\<esc>" . l . 'v' . (L - 1) . "l\<c-g>"
endf

" Multi-line stop selection: lines via the j count, final char via the |N|
" column motion (display col of the last content char).
func! s:select_multiline(stop) abort
    let l = col('.') != 1 ? 'l' : ''
    let dl = a:stop.el - a:stop.l
    let last = a:stop.ec - 1
    if last < 1
        return ''
    endif
    let vcol = virtcol([a:stop.el, last])
    if &sel ==# 'exclusive'
        let vcol -= 1
    endif
    let vcol = max([1, vcol])
    return "\<esc>" . l . 'v' . dl . 'j' . vcol . "|\<c-g>"
endf

" =============== live updates ===============

" Called on CursorMoved / CursorMovedI. Tracks typing inside the current
" stop and shifts every later position on the affected line; the session is
" removed when the cursor leaves the stop (snipMate behavior).
func! snippetary#cursor_update() abort
    let st = snippetary#session()
    if empty(st.stack)
        return ''
    endif

    let exp = st.stack[-1]
    let stop = exp.stops[exp.no]
    let cl = line('.')
    let dollar = col('$')
    let delta = 0
    if cl == st.prev_l
        " same line as the last event: the change length is measurable
        let delta = dollar - st.prev_d
    else
        " cursor moved lines: only keep the session if inside the range
    endif
    if delta != 0
        let exp.changed = 1
        call s:untrack_nested(exp.no)
        " typing happens before the cursor: everything from the insertion
        " point on shifts (except the edited stop itself, which only grows
        " at its end); then mirrors sync with the new content
        let cc = col('.')
        call s:shift_after(cl, cc - delta, delta, stop)
        let stop.ec += delta
        call s:update_mirrors_live(stop)
    endif
    " containment check: cursor must stay inside the stop extent
    let cc = col('.')
    let inside = (cl >= stop.l && cl <= stop.el)
    if inside && cl == stop.l && cc < stop.c
        let inside = 0
    endif
    if inside && cl == stop.el && cc > stop.ec + 1
        let inside = 0
    endif
    if !inside
        call s:remove_top_exp(exp)
        return ''
    endif
    let st.prev_l = cl
    let st.prev_d = col('$')
    return ''
endf

" Untrack stops nested inside the edited stop (their text was replaced).
func! s:untrack_nested(num) abort
    let exp = snippetary#session().stack[-1]
    if !has_key(exp.stops, a:num)
        return
    endif
    let stop = exp.stops[a:num]
    let nested = copy(stop.nested)
    for n in nested
        call s:untrack_nested(n)
        call remove(exp.stops, n)
        call filter(exp.order, 'v:val != n')
    endfor
endf

" Keep mirrors live while typing: replace their text with the stop content.
func! s:update_mirrors_live(stop) abort
    let word = strpart(getline(a:stop.l), a:stop.c - 1, a:stop.ec - a:stop.c)
    for mir in a:stop.mirrors
        if mir.l != mir.el
            continue
        endif
        call s:set_line(mir, word)
    endfor
endf

" Shift every tracked position at or after (line, col) by dcols / dlines.
" An optional 4th arg skips that exact extent (e.g. the object being edited).
func! s:shift_after(line, col, dcols, ...) abort
    let skip = empty(a:000) ? {'__none__': 1} : a:1
    let st = snippetary#session()
    for exp in st.stack
        for n in keys(exp.stops)
            if exp.stops[n] != skip
                call s:shift_extent(exp.stops[n], a:line, a:col, a:dcols)
            endif
            for m in exp.stops[n].mirrors
                if m != skip
                    call s:shift_extent(m, a:line, a:col, a:dcols)
                endif
            endfor
        endfor
    endfor
endf

func! s:shift_extent(x, line, col, dcols) abort
    if a:x.l == a:line && a:x.c >= a:col
        let a:x.c += a:dcols
    endif
    if a:x.el == a:line && a:x.ec > a:col
        let a:x.ec += a:dcols
    endif
endf

" Mirror sync on jump-away: replace mirror text with the stop's content.
func! s:sync_stop(exp) abort
    if !get(a:exp, 'changed', 0)
        return
    endif
    let stop = a:exp.stops[a:exp.no]
    let word = stop.l == stop.el
                \ ? strpart(getline(stop.l), stop.c - 1, stop.ec - stop.c)
                \ : ''
    for mir in stop.mirrors
        if mir.l != mir.el
            continue
        endif
        call s:set_line(mir, word)
    endfor
endf

" Replace oldSize chars at (line, col) with word; shift later same-line
" tracks when the length changes.
func! s:set_line(mir, word) abort
    let line = getline(a:mir.l)
    let begin = strpart(line, 0, a:mir.c - 1)
    let tail = strpart(line, a:mir.c - 1 + a:mir.oldSize)
    call setline(a:mir.l, begin . a:word . tail)
    let change = strlen(a:word) - a:mir.oldSize
    let oldend = a:mir.c + a:mir.oldSize
    let a:mir.oldSize = strlen(a:word)
    let a:mir.ec = a:mir.c + strlen(a:word)
    if change != 0
        call s:shift_after(a:mir.l, oldend, change, a:mir)
    endif
endf

" =============== mapping entry points ===============

" Combined expand-or-jump for the <tab> trigger (runs inside <C-R>=).
func! snippetary#NextOrTrigger() abort
    if pumvisible()
        call feedkeys("\<C-n>", 'n')
        return ''
    endif
    let exp = snippetary#active()
    if !empty(exp)
        return snippetary#jump_keys(1)
    endif
    return snippetary#try_expand()
endf

func! snippetary#try_expand() abort
    let [trig, snip, matched, groups] = snippetary#snip_at(
                \ getline('.')[: col('.') - 2])
    if empty(snip)
        return "\<tab>"
    endif
    return snippetary#do_expand(snip, matched, groups)
endf

func! snippetary#BackwardsSnippet() abort
    if !empty(snippetary#session().stack)
        return snippetary#jump_keys(-1)
    endif
    return "\<s-tab>"
endf

" Capture the visual selection for ${VISUAL}, delete it, enter insert.
func! snippetary#GrabVisual() abort
    let a_save = @a
    try
        silent! normal! gv"ay
        let st = snippetary#session()
        let st.visual = substitute(@a, '\r\?\n$', '', '')
    finally
        let @a = a_save
    endtry
    return ''
endf

" =============== render walk ===============
" Streams the token tree into rendered lines while recording stop extents.
" Rows and cols are relative to the expansion point; do_expand splices them
" into the buffer. The open pile tracks nesting: each nested stop is recorded
" on its parent, and closing a stop captures its rendered content so later
" default text of one placeholder's body: literals + nested defaults
func! s:default_text(dfl) abort
    let out = []
    for lin in a:dfl
        for node in lin
            if type(node) ==# type('')
                call add(out, node)
            elseif node[0] ==# 'p'
                call add(out, s:default_text(node[2]))
            endif
        endfor
    endfor
    return join(out, '')
endfunc

" pre-render the default text of every placeholder in the token tree (the
" t[n] presets: UltiSnips t[n] holds the INITIAL tabstop text even before
" the stop itself renders)
func! s:collect_default(dfl, acc) abort
    for lin in a:dfl
        for node in lin
            if type(node) !=# type('') && node[0] ==# 'p'
                let a:acc[node[1]] = s:default_text(node[2])
            endif
        endfor
    endfor
endfunc

" mirrors can be emitted as copies.

func! s:render(tree, snip, lnum, c, indent, st) abort
    let r = {'lines': [''], 'row': 0, 'stops': {}, 'seen': {},
                \ 'indent': a:indent, 'st': a:st, 'open': [], 'tdefault': {}}
    " pre-collect the default text of every placeholder in the body (the
    " UltiSnips t[n] semantics: t[n] holds the INITIAL tabstop text even
    " before the stop itself renders)
    call s:collect_default(a:tree, r.tdefault)
    call s:wdfl(r, a:tree)
    if !has_key(r.seen, 0)
        call s:stop_open(r, 0)
        call s:stop_close(r)
    endif
    return r
endf

func! s:wdfl(r, dfl) abort
    let first = 1
    for lin in a:dfl
        if !first
            call s:newline(a:r)
        endif
        let first = 0
        for node in lin
            call s:wnode(a:r, node)
        endfor
    endfor
endf

func! s:newline(r) abort
    let a:r.row += 1
    call add(a:r.lines, '')
endf

" Current byte col (1-based) at the end of the rendered row.
func! s:rcol(r) abort
    return strlen(a:r.lines[a:r.row]) + 1
endf

" Emit text; embedded newlines start new rows.
func! s:emit(r, str) abort
    let parts = split(a:str, "\n", 1)
    let i = 0
    for p in parts
        if i != 0
            call s:newline(a:r)
        endif
        let a:r.lines[a:r.row] .= p
        let i += 1
    endfor
endf

" Open tabstop num: nest-tracking on the open parent, pushed on the pile.
func! s:stop_open(r, num) abort
    if len(a:r.open)
        call add(a:r.stops[a:r.open[-1]].nested, a:num)
    endif
    call add(a:r.open, a:num)
    let stop = {'l': a:r.row, 'c': s:rcol(a:r), 'mirrors': [], 'nested': []}
    let a:r.stops[a:num] = stop
    let a:r.seen[a:num] = ''
    return stop
endf

" Close the newest open stop; captures its rendered content.
func! s:stop_close(r) abort
    if empty(a:r.open)
        return
    endif
    let num = remove(a:r.open, -1)
    let stop = a:r.stops[num]
    let stop.el = a:r.row
    let stop.ec = s:rcol(a:r)
    let a:r.seen[num] = s:extent_str(a:r, stop)
endf

" Rendered text of an extent (l, c, el, ec-exclusive) inside the walker.
func! s:extent_str(r, x) abort
    if a:x.l == a:x.el
        return strpart(a:r.lines[a:x.l], a:x.c - 1, a:x.ec - a:x.c)
    endif
    let out = strpart(a:r.lines[a:x.l], a:x.c - 1)
    let i = a:x.l + 1
    while i < a:x.el
        let out .= "\n" . a:r.lines[i]
        let i += 1
    endwhile
    let out .= "\n" . strpart(a:r.lines[a:x.el], 0, a:x.ec - 1)
    return out
endf

func! s:shell_out(cmd) abort
    return substitute(system(a:cmd), '[\r\n]\+$', '', '')
endf

func! s:wnode(r, node) abort
    if type(a:node) == type('')
        call s:emit(a:r, a:node)
        return
    endif
    let kind = a:node[0]
    if kind ==# 't'
        call s:emit(a:r, a:node[1])
    elseif kind ==# 'S'
        call s:emit(a:r, s:shell_out(a:node[1]))
    elseif kind ==# 'V'
        " expose tabstop text to !v (the t[1..9] analog of the UltiSnips
        " python API): already-rendered stops win, pending stops get their
        " pre-rendered default text (UltiSnips t[n] semantics)
        let b:snippetary_t = extend(copy(get(a:r, 'tdefault', {})), copy(a:r.seen))
        " a string result is inserted raw (UltiSnips !v semantics); non-
        " strings go through string()
        let rv = eval(a:node[1])
        call s:emit(a:r, type(rv) ==# type('') ? rv : string(rv))
    elseif kind ==# 'P'
        " python interpolation: skipped (blank)
    elseif kind ==# 'v'
        let st = a:r.st
        call s:emit(a:r, get(st, 'visual', '') !=# '' ? st.visual : a:node[1])
    elseif kind ==# 'm' || kind ==# 'x'
        call s:mirror_node(a:r, a:node)
    elseif kind ==# 'p'
        call s:placeholder_node(a:r, a:node)
    endif
endf

" Mirror node: copy of the tabstop's rendered content. If the tabstop is not
" rendered yet, this is its first occurrence: create the stop here.
func! s:mirror_node(r, node) abort
    let num = a:node[1]
    if !has_key(a:r.seen, num)
        call s:stop_open(a:r, num)
        call s:stop_close(a:r)
        return
    endif
    let stop = a:r.stops[num]
    let str = a:r.seen[num]
    let mir = {'l': a:r.row, 'c': s:rcol(a:r), 'oldSize': strlen(str)}
    call s:emit(a:r, str)
    let mir.el = a:r.row
    let mir.ec = s:rcol(a:r)
    call add(stop.mirrors, mir)
endf

" Placeholder with default content; nested placeholders become nested stops.
func! s:placeholder_node(r, node) abort
    call s:stop_open(a:r, a:node[1])
    call s:wdfl(a:r, a:node[2])
    call s:stop_close(a:r)
endf

