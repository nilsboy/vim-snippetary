" Python-re subset regex engine for 'r' (regular expression) snippet
" triggers. Pure vimscript backtracking VM; the supported grammar covers
" the constructs snippet collections actually use (honza/vim-snippets
" and the UltiSnips docs examples):
"
"   literals, ., \s\S\d\D\w\W\b\B\A\Z, ^ $ anchors, character classes
"   ([...], ranges, negation, shorthand inside classes), groups
"   ((...) capturing, (?:...) non-capturing, (?P<name>...)), alternation
"   (|), quantifiers (* + ? {m,n} {m,} {m} and lazy variants),
"   lookahead ((?=...) (?!...)) and fixed-width lookbehind
"   ((?<=...) (?<!...)).
"   Inline flags: (?i) at pattern start and (?i:...) groups.
"
" Matching follows the UltiSnips engine (snippet/definition/base.py):
" the trigger is re.finditer()d over the text before the cursor, and a
" snippet fires on the first match whose end equals the string end; only
" the matched span is removed before the body expands. Match groups are
" exposed to !v interpolations through b:snippetary_match (the python
" `match.group(n)` analog).
"
" Unknown constructs make compile() fail; such snippets never match
" (fail closed), like the python-skip degradation.

" =============== compile ===============
"
" Patterns compile to a flat instruction list. Ops:
"   CH    [op, char, ci]
"   ANY   [op]
"   CLS   [op, neg, ranges, shorthands, ci]  ranges: [[lo, hi], ...]
"   SH    [op, neg, code]                    code: d w s (negated: D W S)
"   SPL   [op, a, b]                         try a first, then b
"   JMP   [op, a]
"   REP   [op, id, body]                     push a loop frame, enter body
"   REPB  [op, id, min, max, body, exit]     loop bookkeeping (increment)
"   RPC   [op, id, min, max, lazy, body, exit] loop decision
"   GRP   [op, n] / GRPE [op, n]             capture open/close
"   BOL / EOL / A (\A) / Z (\Z) / B (\b) / NB (\B)
"   LA    [op, prog, neg] / LB [op, prog, neg, width]
"   MAT   match; LA/LB progs are self-contained lists.

func! s:bad(msg) abort
    throw 'snippetary-re: ' . a:msg
endf

func! s:emit(op) abort
    call add(s:c.ops, a:op)
    return len(s:c.ops) - 1
endf

func! s:peek() abort
    return s:c.i < len(s:c.pat) ? s:c.pat[s:c.i] : ''
endf

func! s:peek2() abort
    return s:c.i + 1 < len(s:c.pat) ? s:c.pat[s:c.i + 1] : ''
endf

func! s:take() abort
    let ch = s:peek()
    let s:c.i += 1
    return ch
endf

" escape shorthands as range lists (for classes)
func! s:sh_ranges(code) abort
    if a:code ==# 'd'
        return [[48, 57]]
    elseif a:code ==# 'w'
        return [[48, 57], [65, 90], [95, 95], [97, 122]]
    elseif a:code ==# 's'
        return [[9, 13], [32, 32]]
    endif
    return []
endf

" escape inside a class: [kind, value]; 'lit' char, 'sh' shorthand code
func! s:escape_in_class() abort
    let ch = s:take()
    if ch ==# 'd' || ch ==# 'D' || ch ==# 'w' || ch ==# 'W'
                \ || ch ==# 's' || ch ==# 'S'
        return ['sh', tolower(ch)]
    elseif ch ==# 'b'
        return ['lit', nr2char(8)]
    elseif ch ==# 't'
        return ['lit', "\t"]
    elseif ch ==# 'n'
        return ['lit', "\n"]
    elseif ch ==# 'r'
        return ['lit', "\r"]
    elseif ch ==# 'f'
        return ['lit', nr2char(12)]
    elseif ch ==# 'v'
        return ['lit', nr2char(11)]
    elseif ch ==# 'a'
        return ['lit', nr2char(7)]
    elseif ch ==# 'A' || ch ==# 'Z' || ch ==# 'B'
        call s:bad('\A \Z \B are not allowed in a class')
    elseif ch =~# '^[0-9]$'
        call s:bad('backreferences are not supported')
    elseif ch =~# '^[a-zA-Z]$'
        call s:bad('bad escape \' . ch)
    else
        return ['lit', ch]
    endif
endf

" escape outside a class: emits one instruction
func! s:escape() abort
    let ch = s:take()
    if ch ==# 'd' || ch ==# 'D' || ch ==# 'w' || ch ==# 'W'
                \ || ch ==# 's' || ch ==# 'S'
        call s:emit(['SH', ch =~# '^[dws]$' ? 0 : 1, tolower(ch)])
    elseif ch ==# 'b'
        call s:emit(['B'])
    elseif ch ==# 'B'
        call s:emit(['NB'])
    elseif ch ==# 'A'
        call s:emit(['A'])
    elseif ch ==# 'Z'
        call s:emit(['Z'])
    elseif ch ==# 't'
        call s:emit(['CH', "\t", 0])
    elseif ch ==# 'n'
        call s:emit(['CH', "\n", 0])
    elseif ch ==# 'r'
        call s:emit(['CH', "\r", 0])
    elseif ch ==# 'f'
        call s:emit(['CH', nr2char(12), 0])
    elseif ch ==# 'v'
        call s:emit(['CH', nr2char(11), 0])
    elseif ch ==# 'a'
        call s:emit(['CH', nr2char(7), 0])
    elseif ch =~# '^[0-9]$'
        call s:bad('backreferences are not supported')
    elseif ch =~# '^[a-zA-Z]$'
        call s:bad('bad escape \' . ch)
    else
        call s:emit(['CH', ch, 0])
    endif
endf

" character class; emits one CLS instruction
func! s:class(ci) abort
    let neg = 0
    if s:peek() ==# '^'
        let neg = 1
        call s:take()
    endif
    let ranges = []
    let shs = []
    let first = 1
    while 1
        let ch = s:peek()
        if ch ==# ''
            call s:bad('unterminated character class')
        endif
        if ch ==# ']' && !first
            call s:take()
            break
        endif
        let first = 0
        if ch ==# ']'
            call s:take()
            break
        endif
        if ch ==# '\'
            call s:take()
            let [kind, val] = s:escape_in_class()
            if kind ==# 'sh'
                if index(shs, val) < 0
                    call add(shs, val)
                endif
                continue
            endif
            let lo = char2nr(val)
        else
            call s:take()
            let lo = char2nr(ch)
        endif
        " range? a '-' that is neither the last member nor before ]
        if s:peek() ==# '-' && s:peek2() !=# ']' && s:peek2() !=# ''
            call s:take()
            let ch2 = s:take()
            if ch2 ==# '\'
                let [kind2, val2] = s:escape_in_class()
                if kind2 !=# 'lit'
                    call s:bad('shorthand as a range end')
                endif
                let hi = char2nr(val2)
            else
                let hi = char2nr(ch2)
            endif
            if hi < lo
                call s:bad('reversed character range')
            endif
            call add(ranges, [lo, hi])
        else
            call add(ranges, [lo, lo])
        endif
    endwhile
    call s:emit(['CLS', neg, ranges, shs, a:ci])
endf

" parse the group head right after '('; returns a list:
"   ['cap', n, ci]  capturing group
"   ['nc', 0, ci]   non-capturing
"   ['la', neg, ci] / ['lb', neg, ci]  lookaround
func! s:group_head(ci) abort
    if s:peek() !=# '('
        call s:bad('group head expected')
    endif
    call s:take()
    if s:peek() ==# '?'
        call s:take()
        let ch = s:peek()
        if ch ==# ':'
            call s:take()
            return ['nc', 0, a:ci]
        elseif ch ==# '=' || ch ==# '!'
            call s:take()
            return ['la', ch ==# '!', a:ci]
        elseif ch ==# '<'
            call s:take()
            if s:peek() ==# '='
                call s:take()
                return ['lb', 0, a:ci]
            elseif s:peek() ==# '!'
                call s:take()
                return ['lb', 1, a:ci]
            endif
            call s:bad('unknown group syntax (?<...')
        elseif ch ==# 'P'
            call s:take()
            if s:peek() ==# '<'
                call s:take()
                while s:peek() !=# '>' && s:peek() !=# ''
                    call s:take()
                endwhile
                if s:take() !=# '>'
                    call s:bad('unterminated group name')
                endif
                let n = s:c.ngroups + 1
                let s:c.ngroups = n
                return ['cap', n, a:ci]
            endif
            call s:bad('(?P=...) backreferences are not supported')
        elseif ch ==# 'i'
            " inline flag group (?i:...) - only i is supported
            while s:peek() !=# ':' && s:peek() !=# ')' && s:peek() !=# ''
                call s:take()
            endwhile
            if s:take() !=# ':'
                call s:bad('unsupported inline flags')
            endif
            return ['nc', 0, 1]
        else
            call s:bad('unknown group syntax (?' . ch . ')')
        endif
    endif
    let s:c.ngroups = s:c.ngroups + 1
    return ['cap', s:c.ngroups, a:ci]
endf

" copy ops with every address shifted by delta (LA/LB progs are
" self-contained lists and carry no addresses into s:c.ops)
func! s:rebased(ops, delta) abort
    let out = []
    for op in a:ops
        let kind = op[0]
        if kind ==# 'JMP'
            call add(out, [kind, op[1] + a:delta])
        elseif kind ==# 'SPL'
            call add(out, [kind, op[1] + a:delta, op[2] + a:delta])
        elseif kind ==# 'REP'
            call add(out, [kind, op[1], op[2] + a:delta])
        elseif kind ==# 'REPB'
            call add(out, [kind, op[1], op[2], op[3], op[4] + a:delta,
                        \ op[5] + a:delta])
        elseif kind ==# 'RPC'
            call add(out, [kind, op[1], op[2], op[3], op[4], op[5] + a:delta,
                        \ op[6] + a:delta])
        else
            call add(out, op)
        endif
    endfor
    return out
endf

" {m}, {m,n}, {m,} {,n} {,}; malformed -> [0, 0, 0], brace stays literal
func! s:brace_quant() abort
    let save = s:c.i
    call s:take()
    let lo = ''
    let hi = ''
    let part = 0
    while 1
        let ch = s:peek()
        if ch =~# '^[0-9]$'
            if part ==# 0
                let lo .= ch
            else
                let hi .= ch
            endif
            call s:take()
        elseif ch ==# ','
            if part !=# 0
                break
            endif
            let part = 1
            call s:take()
        else
            break
        endif
    endwhile
    if lo ==# '' && hi ==# ''
        let s:c.i = save
        return [0, 0, 0]
    endif
    if s:take() !=# '}'
        let s:c.i = save
        return [0, 0, 0]
    endif
    let min = lo ==# '' ? 0 : str2nr(lo)
    let max = part && hi ==# '' ? -1 : (hi ==# '' ? min : str2nr(hi))
    if max !=# -1 && max < min
        call s:bad('min repeat greater than max repeat')
    endif
    return [min, max, 1]
endf

func! s:bad_repeat_chars() abort
    if s:peek() ==# '*' || s:peek() ==# '+' || s:peek() ==# '?'
        call s:bad('multiple repeat')
    endif
    if s:peek() ==# '{'
        let save = s:c.i
        if s:brace_quant()[2]
            call s:bad('multiple repeat')
        endif
        let s:c.i = save
    endif
endf

" One atom + optional quantifier; emits into s:c.ops. a:start is the
" index the atom was emitted at. Zero-repeat loops get an SPL so the
" empty-iteration exit exists even when the first body attempt fails;
" greedy prefers the body (a), lazy prefers the exit (a).
func! s:atom(start, ci) abort
    let ch = s:peek()
    if ch ==# '('
        let head = s:group_head(a:ci)
        if head[0] ==# 'la' || head[0] ==# 'lb'
            " compile the inner pattern into its own self-contained
            " program; lookarounds are not quantifiable
            let keep = s:c.ops
            let saveg = s:c.ngroups
            let s:c.ops = []
            let s:c.ngroups = 0
            call s:alt(head[2])
            if s:take() !=# ')'
                call s:bad('unterminated (')
            endif
            call s:emit(['MAT'])
            let sub = s:c.ops
            let s:c.ops = keep
            let s:c.ngroups = saveg
            if head[0] ==# 'la'
                call s:emit(['LA', sub, head[1]])
            else
                call s:emit(['LB', sub, head[1], s:fixed_width(sub)])
            endif
            if s:peek() ==# '*' || s:peek() ==# '+' || s:peek() ==# '?'
                call s:bad('nothing to repeat')
            endif
            return
        endif
        if head[0] ==# 'cap'
            call s:emit(['GRP', head[1]])
        endif
        call s:alt(head[2])
        if s:take() !=# ')'
            call s:bad('unterminated (')
        endif
        if head[0] ==# 'cap'
            call s:emit(['GRPE', head[1]])
        endif
    elseif ch ==# '['
        call s:take()
        call s:class(a:ci)
    elseif ch ==# '\'
        call s:take()
        call s:escape()
    elseif ch ==# ''
        call s:bad('pattern ended unexpectedly')
    else
        call s:take()
        if ch ==# '.'
            call s:emit(['ANY'])
        elseif ch ==# '^'
            call s:emit(['BOL'])
        elseif ch ==# '$'
            call s:emit(['EOL'])
        else
            call s:emit(['CH', ch, a:ci])
        endif
    endif
    call s:quantify(a:start)
endf

" wrap the last atom (ops [a:start ..]) with a quantifier when one
" follows; a malformed brace stays a literal atom per python
func! s:quantify(start) abort
    let ch = s:peek()
    if ch ==# '{'
        let [min, max, ok] = s:brace_quant()
        if !ok
            call s:emit(['CH', '{', 0])
            return
        endif
    elseif ch ==# '*'
        let min = 0
        let max = -1
        call s:take()
    elseif ch ==# '+'
        let min = 1
        let max = -1
        call s:take()
    elseif ch ==# '?'
        let min = 0
        let max = 1
        call s:take()
    else
        return
    endif
    let lazy = 0
    if s:peek() ==# '?'
        let lazy = 1
        call s:take()
    endif
    call s:bad_repeat_chars()
    " anchors and lookarounds cannot be quantified (python: 'nothing to
    " repeat'); pure empty groups may
    let consumable = 0
    let asserting = 0
    for op in s:c.ops[a:start : -1]
        if index(['CH', 'ANY', 'CLS', 'SH'], op[0]) >= 0
            let consumable = 1
        endif
        if index(['BOL', 'EOL', 'A', 'Z', 'B', 'NB', 'LA', 'LB'], op[0]) >= 0
            let asserting = 1
        endif
    endfor
    if asserting && !consumable
        call s:bad('nothing to repeat')
    endif
    " re-wrap: [SPL] REP sits before the atom, the atom follows
    " (rebased), then REPB and RPC close with the exit behind them
    let len0 = len(s:c.ops)
    let atomops = remove(s:c.ops, a:start, -1)
    if min ==# 0
        call s:emit(['SPL', -1, -1])
    endif
    let spl = len(s:c.ops) - 1
    let body = len(s:c.ops) + 1
    call s:emit(['REP', s:c.loops, body])
    for op in s:rebased(atomops, body - a:start)
        call add(s:c.ops, op)
    endfor
    let exit = body + len(atomops) + 2
    call add(s:c.ops, ['REPB', s:c.loops, min, max, body, exit])
    call add(s:c.ops, ['RPC', s:c.loops, min, max, lazy, body, exit])
    if min ==# 0
        if lazy
            let s:c.ops[spl] = ['SPL', exit, body - 1]
        else
            let s:c.ops[spl] = ['SPL', body - 1, exit]
        endif
    endif
    let s:c.loops += 1
    if len(s:c.ops) !=# len0 + (min ==# 0 ? 4 : 3)
        call s:bad('quantifier re-wrap failed')
    endif
endf

" a sequence of atoms until '|' / ')' / end; returns the start index
func! s:seq(ci) abort
    while 1
        let ch = s:peek()
        if ch ==# '' || ch ==# '|' || ch ==# ')'
            return
        endif
        call s:atom(len(s:c.ops), a:ci)
    endwhile
endf

" fixed width of a lookbehind program, or -1 (only straight sequences
" of single-char atoms count; alternatives would have to agree)
func! s:fixed_width(ops) abort
    let w = 0
    for op in a:ops
        let kind = op[0]
        if kind ==# 'CH' || kind ==# 'ANY' || kind ==# 'CLS' || kind ==# 'SH'
            let w += 1
        elseif kind ==# 'GRP' || kind ==# 'GRPE' || kind ==# 'MAT'
            continue
        else
            return -1
        endif
    endfor
    return w
endf

" alternation of sequences
func! s:alt(ci) abort
    let outer = s:c.ops
    let branches = []
    while 1
        let s:c.ops = []
        call s:seq(a:ci)
        call add(branches, s:c.ops)
        if s:peek() ==# '|'
            call s:take()
        else
            break
        endif
    endwhile
    let s:c.ops = outer
    if len(branches) ==# 1
        for op in s:rebased(branches[0], len(outer))
            call add(s:c.ops, op)
        endfor
        return
    endif
    let splitters = []
    let jmps = []
    let i = 0
    for b in branches
        if len(branches) > 1
            let splitters += [s:emit(['SPL', len(s:c.ops) + 1, -1])]
        endif
        for op in s:rebased(b, len(s:c.ops))
            call add(s:c.ops, op)
        endfor
        if i !=# len(branches) - 1
            let jmps += [s:emit(['JMP', -1])]
        endif
        let i += 1
    endfor
    let tail = len(s:c.ops)
    for j in jmps
        let s:c.ops[j][1] = tail
    endfor
    let i = 0
    for sp in splitters
        let nxt = i + 1 < len(splitters) ? splitters[i + 1] : tail
        let s:c.ops[sp][2] = nxt
        let i += 1
    endfor
endf

" =============== VM ===============

func! s:is_word(ch) abort
    return a:ch =~# '^[0-9A-Za-z_]$'
endf

" loop frames: list of [id, count, iterstart]
func! s:repfind(reps, id) abort
    for f in a:reps
        if f[0] ==# a:id
            return f
        endif
    endfor
    return [a:id, -1, -1]
endf

func! s:reppop(reps, id) abort
    let out = []
    for f in a:reps
        if f[0] !=# a:id
            call add(out, f)
        endif
    endfor
    return out
endf

func! s:repset(reps, id, key, val) abort
    let out = []
    for f in a:reps
        if f[0] ==# a:id
            call add(out, [f[0], a:key ==# 1 ? a:val : f[1],
                        \ a:key ==# 2 ? a:val : f[2]])
        else
            call add(out, f)
        endif
    endfor
    return out
endf

func! s:copreps(reps) abort
    let out = []
    for f in a:reps
        call add(out, copy(f))
    endfor
    return out
endf

func! s:capset(caps, n, s, e) abort
    let out = copy(a:caps)
    let out[a:n] = [a:s, a:e]
    return out
endf

func! s:group_text(text, caps) abort
    let out = {}
    for [n, span] in items(a:caps)
        if span[1] >= 0
            let out[str2nr(n)] = strpart(a:text, span[0], span[1] - span[0])
        endif
    endfor
    return out
endf

func! s:eqci(a, b) abort
    return tolower(a:a) ==# tolower(a:b)
endf

func! s:cls_test(ch, neg, ranges, shs, ci) abort
    let c = char2nr(a:ch)
    let cf = char2nr(tolower(a:ch))
    let hit = 0
    for r in a:ranges
        if c >= r[0] && c <= r[1]
            let hit = 1
            break
        endif
        if a:ci
            let lo = char2nr(tolower(nr2char(r[0])))
            let hi = char2nr(tolower(nr2char(r[1])))
            if cf >= lo && cf <= hi
                let hit = 1
                break
            endif
        endif
    endfor
    if !hit
        for sh in a:shs
            if sh ==# 'd'
                let hit = c >= 48 && c <= 57
            elseif sh ==# 'w'
                let hit = s:is_word(a:ch)
            elseif sh ==# 's'
                let hit = (c >= 9 && c <= 13) || c ==# 32
            endif
            if hit
                break
            endif
        endfor
    endif
    return a:neg ? !hit : hit
endf

func! s:sh_test(ch, neg, code) abort
    let c = char2nr(a:ch)
    let hit = 0
    if a:code ==# 'd'
        let hit = c >= 48 && c <= 57
    elseif a:code ==# 'w'
        let hit = s:is_word(a:ch)
    elseif a:code ==# 's'
        let hit = (c >= 9 && c <= 13) || c ==# 32
    endif
    return a:neg ? !hit : hit
endf

" One anchored attempt. When a:req_end >= 0 the match must end exactly
" there (lookbehind runs return that way).
func! s:run(ops, text, start, req_end) abort
    let len = strlen(a:text)
    let stack = [[0, a:start, {}, []]]
    let guard = 0
    while !empty(stack)
        let guard += 1
        if guard > 20000
            " pathological pattern: fail closed
            return {}
        endif
        let [pc, pos, caps, reps] = remove(stack, -1)
        let alive = 1
        while alive
            if pc >= len(a:ops)
                return {}
            endif
            let op = a:ops[pc]
            let kind = op[0]
            if kind ==# 'MAT'
                if a:req_end < 0 || pos ==# a:req_end
                    return {'s': a:start, 'e': pos,
                                \ 'whole': strpart(a:text, a:start,
                                \ pos - a:start),
                                \ 'groups': s:group_text(a:text, caps)}
                endif
                let alive = 0
            elseif kind ==# 'CH'
                if pos < len && strpart(a:text, pos, 1) ==# op[1]
                    let pos += 1
                    let pc += 1
                elseif op[2] && pos < len
                            \ && s:eqci(strpart(a:text, pos, 1), op[1])
                    let pos += 1
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'ANY'
                if pos < len
                    let pos += 1
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'CLS'
                if pos < len && s:cls_test(strpart(a:text, pos, 1),
                            \ op[1], op[2], op[3], op[4])
                    let pos += 1
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'SH'
                if pos < len && s:sh_test(strpart(a:text, pos, 1),
                            \ op[1], op[2])
                    let pos += 1
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'SPL'
                call add(stack, [op[2], pos, copy(caps), s:copreps(reps)])
                let pc = op[1]
            elseif kind ==# 'JMP'
                let pc = op[1]
            elseif kind ==# 'REP'
                let reps = copy(reps)
                call add(reps, [op[1], 0, pos])
                let pc = op[2]
            elseif kind ==# 'REPB'
                let frame = s:repfind(reps, op[1])
                let c = frame[1] + 1
                let reps = s:repset(reps, op[1], 1, c)
                if c < op[2]
                    let reps = s:repset(reps, op[1], 2, pos)
                    let pc = op[4]
                else
                    let pc += 1
                endif
            elseif kind ==# 'RPC'
                let frame = s:repfind(reps, op[1])
                let c = frame[1]
                if pos ==# frame[2]
                    let reps = s:reppop(reps, op[1])
                    let pc = op[6]
                elseif c < op[2]
                    let reps = s:repset(reps, op[1], 2, pos)
                    let pc = op[5]
                elseif op[3] >= 0 && c >= op[3]
                    let reps = s:reppop(reps, op[1])
                    let pc = op[6]
                elseif op[4]
                    let pushreps = s:repset(s:copreps(reps), op[1], 2, pos)
                    call add(stack, [op[5], pos, copy(caps), pushreps])
                    let reps = s:reppop(reps, op[1])
                    let pc = op[6]
                else
                    call add(stack, [op[6], pos, copy(caps),
                                \ s:reppop(s:copreps(reps), op[1])])
                    let reps = s:repset(reps, op[1], 2, pos)
                    let pc = op[5]
                endif
            elseif kind ==# 'GRP'
                let caps = s:capset(caps, op[1], pos, -1)
                let pc += 1
            elseif kind ==# 'GRPE'
                if has_key(caps, op[1]) && caps[op[1]][1] < 0
                    let caps = copy(caps)
                    let caps[op[1]] = [caps[op[1]][0], pos]
                endif
                let pc += 1
            elseif kind ==# 'BOL' || kind ==# 'A'
                if pos ==# 0
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'EOL' || kind ==# 'Z'
                if pos ==# len
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'B' || kind ==# 'NB'
                let left = pos > 0 && s:is_word(strpart(a:text, pos - 1, 1))
                let right = pos < len && s:is_word(strpart(a:text, pos, 1))
                if (left !=# right) ==# (kind ==# 'B')
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'LA'
                let sub = s:run(op[1], a:text, pos, -1)
                if (!empty(sub)) !=# op[2]
                    let pc += 1
                else
                    let alive = 0
                endif
            elseif kind ==# 'LB'
                if op[3] < 0
                    " variable-width lookbehind: fail closed
                    let alive = 0
                else
                    let ok = 0
                    if pos - op[3] >= 0
                        let sub = s:run(op[1], a:text, pos - op[3], pos)
                        let ok = !empty(sub)
                    endif
                    " a negative lookbehind before the string start is
                    " true: there is no preceding character
                    if ok !=# op[2]
                        let pc += 1
                    else
                        let alive = 0
                    endif
                endif
            else
                call s:bad('unknown op ' . kind)
            endif
        endwhile
    endwhile
    return {}
endf

" =============== public ===============

let s:cache = {}

func! snippetary#re#program(pattern) abort
    if has_key(s:cache, a:pattern)
        return s:cache[a:pattern]
    endif
    let prog = snippetary#re#compile(a:pattern)
    let s:cache[a:pattern] = prog
    if len(s:cache) > 64
        call remove(s:cache, keys(s:cache)[0])
    endif
    return prog
endf

func! snippetary#re#compile(pattern) abort
    let s:c = {'pat': a:pattern, 'i': 0, 'ngroups': 0, 'ops': [],
                \ 'loops': 0}
    try
        let ci = 0
        " leading inline flag: (?i) (possibly repeated)
        while strpart(a:pattern, s:c.i, 4) ==# '(?i)'
            let s:c.i += 4
            let ci = 1
        endwhile
        call s:alt(ci)
        if s:c.i !=# len(a:pattern)
            call s:bad('unmatched closing )')
        endif
        call s:emit(['MAT'])
        return {'ok': 1, 'ops': s:c.ops, 'ngroups': s:c.ngroups}
    catch /snippetary-re:/
        let g:snippetary_re_error = v:exception
        return {'ok': 0}
    endtry
endf

" UltiSnips r-semantics: finditer over the text, snippet fires on the
" first match ending at the string end. Returns {} or
" {'s', 'e', 'whole', 'groups': {num: text}}
func! snippetary#re#matchend(prog, text) abort
    if !a:prog.ok
        return {}
    endif
    try
        return s:matchend(a:prog, a:text)
    catch /snippetary-re:/
        return {}
    endtry
endf

func! s:matchend(prog, text) abort
    let len = strlen(a:text)
    let s = 0
    while s <= len
        let m = s:run(a:prog.ops, a:text, s, -1)
        if !empty(m)
            if m.e ==# len
                return m
            endif
            let s = m.e > s ? m.e : s + 1
        else
            let s += 1
        endif
    endwhile
    return {}
endf
