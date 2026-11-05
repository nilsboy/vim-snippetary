"" snippetary: parsing of UltiSnips-format snippet files and snippet bodies.

" Escape set used at token level: backslash followed by one of these produces
" that single char. Backslash before anything else stays literal
" (UltiSnips-compatible; keeps latex-like \-sequences intact).
let s:esc = ['{', '}', '$', '`']

func! snippetary#parse#_isesc(s, i) abort
    return a:i+1 < len(a:s.text) && a:s.text[a:i] ==# '\'
                \ && index(s:esc, a:s.text[a:i+1]) >= 0
endf

" Walk the raw inner text of a `${...}` default (or `${VISUAL:...}`). Consumes
" the closing brace, returns the raw inner text with escape pairs preserved
" for the nested parse. Escapes of \{ \} \\ count as literal and do not shift
" the brace depth.
func! snippetary#parse#till_closing_brace(s) abort
    let rv = ''
    let depth = 1
    while a:s.pos < len(a:s.text)
        let c = a:s.text[a:s.pos]
        if c ==# '\' && a:s.pos+1 < len(a:s.text)
                    \ && index(['\\', '{', '}'], a:s.text[a:s.pos+1]) >= 0
            let rv .= a:s.text[a:s.pos : a:s.pos+1]
            let a:s.pos += 2
            continue
        endif
        if c ==# '{'
            let depth += 1
        elseif c ==# '}'
            let depth -= 1
            if depth == 0
                let a:s.pos += 1
                break
            endif
        endif
        let rv .= c
        let a:s.pos += 1
    endwhile
    return rv
endf

" Read till (and consuming) an unescaped char from a:chars; backslash+char
" (char in a:chars) is consumed and kept as a pair. The stopping char is left
" in a:s.last.
func! snippetary#parse#till_unescaped(s, chars) abort
    let rv = ''
    let clist = split(a:chars, '\zs')
    let a:s.last = ''
    while a:s.pos < len(a:s.text)
        let c = a:s.text[a:s.pos]
        if c ==# '\' && a:s.pos+1 < len(a:s.text)
                    \ && len(filter(copy(clist), 'v:val ==# a:s.text[a:s.pos+1]'))
            let rv .= a:s.text[a:s.pos : a:s.pos+1]
            let a:s.pos += 2
            continue
        endif
        if len(filter(copy(clist), 'v:val ==# c'))
            let a:s.pos += 1
            let a:s.last = c
            break
        endif
        let rv .= c
        let a:s.pos += 1
    endwhile
    return rv
endf

" Resolve escapes of { } $ ` producing the bare char; other backslashes stay.
func! snippetary#parse#unescape(str) abort
    let out = ''
    let i = 0
    let L = len(a:str)
    while i < L
        if a:str[i] ==# '\' && i+1 < L && index(s:esc, a:str[i+1]) >= 0
            let out .= a:str[i+1]
            let i += 2
        else
            let out .= a:str[i]
            let i += 1
        endif
    endwhile
    return out
endf

func! snippetary#parse#_emit(line, str) abort
    if len(a:line) && type(a:line[-1]) == type('')
        let a:line[-1] .= a:str
    else
        call add(a:line, a:str)
    endif
endf

" Tokenize snippet text into lines of nodes:
"   ['t', str]        literal text (already unescaped)
"   ['p', num, dfl]   placeholder, dfl = default lines (nested tokens)
"   ['m', num]        mirror / bare $N
"   ['x', num]        mirror with a (dropped) transformation
"   ['v', str]        VISUAL placeholder, resolved to static text at expand
"   ['S', cmd]        shell code interpolation, run at expand
"   ['V', expr]       viml code interpolation, run at expand
"   ['P']             python interpolation, unsupported (blank)
func! snippetary#parse#tokens(text) abort
    let s = {'text': a:text, 'pos': 0, 'last': ''}
    let lines = []
    let line = []
    let L = len(a:text)
    while s.pos < L
        let c = a:text[s.pos]
        if snippetary#parse#_isesc(s, s.pos)
            call snippetary#parse#_emit(line, a:text[s.pos+1])
            let s.pos += 2
        elseif c ==# '$' && s.pos+1 < L && a:text[s.pos+1] ==# '{'
            call s:dollar_brace(s, line)
        elseif c ==# '$'
            call s:dollar_bare(s, line)
        elseif c ==# '`'
            call s:backtick(s, line)
        elseif c ==# "\n"
            call add(lines, line)
            let line = []
            let s.pos += 1
        else
            call snippetary#parse#_emit(line, c)
            let s.pos += 1
        endif
    endwhile
    call add(lines, line)
    return lines
endf

" `${...}` at pos. VISUAL / placeholder / transform / choices / literal.
func! s:dollar_brace(s, line) abort
    let T = a:s.text
    let head = T[a:s.pos : a:s.pos+9]
    if head =~# '^\${VISUAL[:}/]'
        let a:s.pos += 8
        if a:s.pos < len(T) && T[a:s.pos] ==# ':'
            let a:s.pos += 1
        endif
        let inner = snippetary#parse#till_unescaped(a:s, '/}')
        if a:s.last ==# '/'
            call snippetary#parse#till_unescaped(a:s, '/')
            call snippetary#parse#till_unescaped(a:s, '/')
            call snippetary#parse#till_closing_brace(a:s)
        endif
        call add(a:line, ['v', snippetary#parse#unescape(inner)])
        return
    endif
    if head =~# '^\${[0-9]'
        let a:s.pos += 2
        let num = s:number(a:s)
        let c = a:s.pos < len(T) ? T[a:s.pos] : '}'
        if c ==# ':'
            let a:s.pos += 1
            let inner = snippetary#parse#till_closing_brace(a:s)
            call add(a:line, ['p', num, snippetary#parse#tokens(inner)])
        elseif c ==# '/'
            let a:s.pos += 1
            let tr = s:transform(a:s)
            call add(a:line, ['x', num, tr])
        elseif c ==# '|'
            let a:s.pos += 1
            let choices = s:choices(a:s)
            call add(a:line, ['p', num, snippetary#parse#tokens(choices[0])])
        elseif c ==# '}'
            let a:s.pos += 1
            call add(a:line, ['p', num, [['']]])
        else
            call snippetary#parse#_emit(a:line, '$')
        endif
        return
    endif
    " literal `${...` (shell syntax or malformed)
    call snippetary#parse#_emit(a:line, '$')
    let a:s.pos += 1
endf

func! s:number(s) abort
    let num = ''
    while a:s.pos < len(a:s.text) && a:s.text[a:s.pos] =~# '\d'
        let num .= a:s.text[a:s.pos]
        let a:s.pos += 1
    endwhile
    return num ==# '' ? 0 : str2nr(num)
endf

" consumes num/ search/ replace/ opts}; the ${num/ part is already consumed.
func! s:transform(s) abort
    let search = snippetary#parse#till_unescaped(a:s, '/')
    let replace = snippetary#parse#till_unescaped(a:s, '/')
    let opts = snippetary#parse#till_closing_brace(a:s)
    return {'search': search, 'replace': replace, 'opts': opts}
endf

" consumes the choices after the opening | was consumed.
func! s:choices(s) abort
    let raw = snippetary#parse#till_unescaped(a:s, '|')
    let choices = []
    let cur = ''
    let i = 0
    while i < len(raw)
        let c = raw[i]
        if c ==# '\' && i+1 < len(raw)
            let cur .= raw[i:i+1]
            let i += 2
        elseif c ==# ','
            call add(choices, substitute(cur, '\\,', ',', 'g'))
            let cur = ''
            let i += 1
        else
            let cur .= c
            let i += 1
        endif
    endwhile
    call add(choices, substitute(cur, '\\,', ',', 'g'))
    call snippetary#parse#till_closing_brace(a:s)
    return choices
endf

" bare $N at pos.
func! s:dollar_bare(s, line) abort
    let a:s.pos += 1
    if a:s.pos < len(a:s.text) && a:s.text[a:s.pos] =~# '\d'
        let num = s:number(a:s)
        call add(a:line, ['m', num])
    else
        call snippetary#parse#_emit(a:line, '$')
    endif
endf

" backtick code at pos: !v expr, !p (skip), shell.
func! s:backtick(s, line) abort
    let a:s.pos += 1
    let code = snippetary#parse#till_unescaped(a:s, '`')
    if code[:2] ==# '!v '
        call add(a:line, ['V', substitute(code[2:], '\s\+$', '', '')])
    elseif code[:1] ==# '!p'
        call add(a:line, ['P'])
    else
        call add(a:line, ['S', code])
    endif
endf

"" """""""""""""""""""""" .snippets file parsing """"""""""""""""""""""""

" Parse the 'snippet ...' header line (without the keyword). Mimics the
" UltiSnips logic for quoted multi-word triggers, description and options.
" Returns ['trig', desc, opts] or ['ERROR', msg].
func! snippetary#parse#header(rest) abort
    let remain = substitute(a:rest, '^\s\+\|\s\+$', '', 'g')
    let words = split(remain)
    let opts = ''
    if len(words) > 2 && stridx(words[-1], '"') < 0 && words[-2][-1 :] ==# '"'
        let opts = remove(words, -1)
        let remain = substitute(strpart(remain, 0, len(remain) - len(opts)), '\s\+$', '', '')
    endif
    let remain = substitute(remain, '^\s\+\|\s\+$', '', 'g')
    let desc = ''
    if len(split(remain)) > 1 && remain[-1 :] ==# '"'
        let left = strridx(remain[:-2], '"')
        if left >= 0 && left != 0
            let desc = remain[left :]
            let remain = remain[: left-1]
        endif
    endif
    let desc = s:unwrap(desc)
    let trig = substitute(remain, '^\s\+\|\s\+$', '', 'g')
    if len(split(trig)) > 1 || stridx(opts, 'r') >= 0
        if trig[0] != trig[-1:] || trig[0] =~# '\w'
            return ['ERROR', 'invalid multiword trigger']
        endif
        let trig = trig[1:-2]
    endif
    return [trig, desc, opts]
endf

func! s:unwrap(desc) abort
    if a:desc[:0] ==# '"' && a:desc[-1 :] ==# '"' && len(a:desc) > 1
        return a:desc[1:-2]
    endif
    return a:desc
endf

" Parse the contents (list of lines) of one .snippets file.
" Returns {'snips': [...], 'extends': [...], 'python': 0|1, 'errors': [...]}
" snips items: {'trig':, 'desc':, 'opts':, 'pri':, 'body': raw-string}
func! snippetary#parse#snippets_file(lines) abort
    let info = {'snips': [], 'extends': [], 'python': 0, 'errors': []}
    let pri = 0
    let in_snip = 0
    let in_global = 0
    let trig = ''
    let desc = ''
    let opts = ''
    let body = []
    for raw in a:lines
        let first = s:rstrip(raw)
        let head = matchstr(first, '^\S\+')
        let tail = first[len(head) :]
        if in_snip
            if s:rstrip(raw) ==# 'endsnippet'
                call add(info.snips, {
                            \ 'trig': trig, 'desc': desc, 'opts': opts,
                            \ 'pri': pri, 'body': join(body, "\n")})
                let in_snip = 0
            else
                call add(body, raw)
            endif
            continue
        elseif in_global
            if s:rstrip(raw) ==# 'endglobal'
                let in_global = 0
            endif
            continue
        endif
        if head ==# '' || head[0] ==# '#'
            continue
        endif
        if head ==# 'snippet'
            let h = snippetary#parse#header(tail)
            if len(h) == 2
                call add(info.errors, h[1])
            elseif h[0] !=# ''
                let trig = h[0]
                let desc = h[1]
                let opts = h[2]
                let body = []
                let in_snip = 1
            endif
        elseif head ==# 'global'
            let in_global = 1
            let info.python = 1
        elseif head ==# 'extends'
            for ft in split(tail, ',')
                let ft = substitute(ft, '^\s\+\|\s\+$', '', 'g')
                if ft !=# ''
                    call add(info.extends, ft)
                endif
            endfor
        elseif head ==# 'priority'
            let pri = s:to_num(tail)
        elseif head ==# 'clearsnippets' || head ==# 'context'
                    \ || head ==# 'pre_expand' || head ==# 'post_expand'
                    \ || head ==# 'post_jump' || head ==# 'post_finish'
                    \ || head ==# 'version'
            continue
        else
            call add(info.errors, 'invalid line: ' . s:rstrip(raw))
        endif
    endfor
    if in_snip
        call add(info.snips, {
                    \ 'trig': trig, 'desc': desc, 'opts': opts,
                    \ 'pri': pri, 'body': join(body, "\n")})
    endif
    return info
endf

func! s:rstrip(line) abort
    return substitute(a:line, '\s\+$', '', '')
endf

func! s:to_num(str) abort
    return str2nr(substitute(a:str, '^\s\+\|\s\+$', '', 'g'))
endf