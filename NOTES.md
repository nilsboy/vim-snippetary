# snippetary — notes

## Goal
A classic (pure) vimscript snippet engine that works with UltiSnips-formatted
`.snippets` files (placeholders, mirrors, `extends`, `priority`, options),
tested with vader. The editor available in this environment is nvim 0.9.5
(`/usr/bin/vim` is symlinked to it via alternatives); `vim.tiny` exists but has
`-eval` so it cannot run plugins. Neovim 0.9.5 has no text properties
(`exists('*prop_add') == 0`).

## Engine architecture (final decisions)

No sentinel characters, no text props — pure (line, col) bookkeeping, the
approach proven by snipMate (garbas fork, autoload/snipmate/*.vim). All
mappings use the snipMate pattern:

    inoremap <silent> <Plug>... <C-R>=Func()<CR>
    snoremap <silent> <Plug>... <Esc>a<C-R>=Func()<CR>

Functions run while still inside insert-mode evaluation, may perform buffer
surgery and `cursor()` placement, and RETURN a string that is then processed
as keystrokes: `"\<esc>l v … \<c-g>"` enters select mode over n chars
(verified empirically: end state = select mode `s`, typing replaces the
selection). An empty return leaves the cursor in insert mode at the position
set inside the evaluation (verified: typing lands correctly).

### State (buffer-local)

    b:snippetary = {
      'snips': {},       trigger -> [snip, ...] sorted by priority desc
      'ftdone': [],      scopes already merged into 'snips'
      'stack': [exp, .]  active expansions, innermost last
      'visual': '',      text captured from the last visual+Tab (for ${VISUAL})
      'pywarn': 0        warned about !p interpolations once
      'prev_l': 0, 'prev_c': 0, 'prev_d': 0
    }

    exp = {                      one expansion
      'no': current tabstop number,
      'order': [1, 2, ...0]      sorted stop numbers, 0 (exit) always last,
      'stops': {n: stop},        n = tabstop number,
      'opts': '...'              snippet options
    }

    stop = {                     one tabstop
      'l': start line,    'c': start byte col (1-based),
      'el': end line,     'ec': end byte col, EXCLUSIVE (one past last char),
      'mirrors': [mir, .],   mirror dicts: {'l','c','el','ec','oldSize'}
      'nested': [n, .],      tabstop numbers nested inside the default
    }

The current expansion is `stack[-1]`; its current stop is `stops[no]`.
`col('$')` of the edited line and (prev_l, prev_c) bookkeeping live in
`b:snippetary.prev_*`.

### Live updates (CursorMoved / CursorMovedI handlers)

1. If no stack: return. Let stop = current stop, exp = current expansion.
2. If `line('.') != prev_l`: (cursor changed line) — no delta info; if the
   cursor stayed inside the stop's line range keep going, else remove() the
   session (state only — buffer keeps the plain text, nothing leaks).
3. Else: `delta = col('$') - prev_d`; if delta != 0:
   - mark exp.changed, untrack `nested` stops of the current stop (their text
     was replaced by the user's typing) — recursively;
   - for every track (stops + mirrors of every exp in the stack) on the same
     line with `c > stop_c`: `col += delta` (snipMate update rule; the current
     stop's own extent start never moves);
   - `stop.ec += delta`; shift-stop-ends too;
   - mirrors: current stop's mirrors get their content replaced with the stop
     text between (c..ec), plus same-size bookkeeping; replacement that
     changes length shifts later same-line tracks (snipMate dance):
     `set_line(line, col, oldSize, newWord)`.
4. Update prev_* (line, col, col('$')).

### Jumps

`order` = sorted stop numbers, exit stop 0 placed last by finalize (UltiSnips
`finalize`: $0 = at end of body if not defined). Walking forward: next entry
in order; backward: previous. Entering NON-zero stop:
- cursor(snippet stop start col) — note insert-mode col semantics: col('.') in
  insert = insertion point; after `\<esc>` the normal cursor is on the char to
  the left, so an `l` motion fixes it (snipMate trick); col==1 edge → no l.
- stop content length L = ec - sc … if L == 0: return '' (stay in insert at
  the placed point). Else return keys selecting the content in SELECT mode:
  inclusive `&sel`: `\<esc>` . l . "v" . (L-1) . "l" . "\<c-g>",
  exclusive: `\<esc>` . l . "v" . L . "l" . "\<c-g>".
  Multi-line selections are entered with the same pattern using a `j` count
  for the line delta and a final `|N|` to the end column computed from
  virtcol() (multibyte-safe).
Forward past the last real stop: the walk reaches 0 (exit): cursor placed at
the exit point's position and the session is removed (snipMate-style). If the
snippet opts contain `x`, additionally exit to normal mode.
Backward from the first real stop: their wrap goes to 0 as well but session is
kept (backwards). We keep that behavior.

### Mirrors (live)

While typing inside stop n, every CursorMovedI: mirrors get
`set_line(mir.l, mir.c, oldSize, newWord)` where newWord = the stop's full
content — single-line only in v1 (multi-line mirror contents degrade to their
first line, documented limitation; TODO item added). Each mirror's own length
change shifts later same-line tracks (update dance). `oldSize` is stored per
mirror and initialized at expansion (build) time to the rendered default
length.

### Build (expansion)

`snippetary#parse#tokens(body)` returns lines of nodes:
    ['t', str] literal text (unescaped)
    ['p', n, dfl]  placeholder (dfl = nested node lines)
    ['m', n]       mirror / bare $N
    ['x', n]       mirror with transformation (transformation dropped, v1)
    ['v', str]     VISUAL placeholder (resolved to static text at expand)
    ['S', cmd]     shell code (system(), trailing newline chomped)
    ['V', expr]    viml code evaluated at expand
    ['P']          python interpolation -> blank (no warning)

Expansion algorithm (snippetary#do_expand, inside <C-R>=):
1. lnum/c/line; indent = leading whitespace of the line; matched = trigger
   text just left of the cursor; before/after slices.
2. Render the tree into lines while ALSO recording stops: render state walks
   (row, col) — the walk emits text, resolves interpolations, records every
   placeholder's extent and creates mirrors as plain copies of the primary's
   rendered default (first occurrence in render order = primary; its own
   nested placeholders are rendered inline and recorded; later occurrences =
   mirrors with a snapshot of the rendered content).
   Tab conversion + indentation per the UltiSnips launch() rule:
   - body line 1: leading tabs -> proper indent (ntabs_to_proper_indent),
     spaces preserved;
   - other lines: leading tabs -> proper indent + expansion indent prepended;
   - 't' option: keep tabs; 'm' option: rstrip lines.
3. Line surgery: setline(first, prefix + body0); append middle lines; join
   after-cursor text to the last body line.
4. If no $0 in tree: implicit exit stop 0 recorded at the end of the last
   body line (UltiSnips finalize).
5. exp pushed on stack, prev = cursor state, then set_stop(first-real)
   → returns the select keys (or '' for empty first stop).

### Trigger matching (UltiSnips verbatim semantics)

`before` = chars before the cursor on the line. words = trailing
whitespace-delim tokens (raw substring form). Per option:
- default: words ==# trigger
- 'w': words ==# trigger AND word-boundary between the preceding char and the
  trigger's first char (keyword difference via iskeyword)
- 'i': the trailing word-run ends with the trigger (words endswith it),
- 'p': trigger starts with words (the typed prefix) — v1: SKIP (rare),
- 'r', 'e', 'A': skip (never match; python-dependent), 's': skip.
- 'b' (post check, applied with a stripped match): text before the matched
  part must be only spaces/tabs.
Priority: best = highest pri among matches (ties: keep first found).

### File loading

`g:snippetary_snippet_dirs` (default: `['UltiSnips']`): names searched in
runtimepath, absolute paths used directly; `g:UltiSnipsSnippetDirectories`
honored if the user has it set (compat) unless override. File patterns per
scope: `ft.snippets`, `ft_*.snippets`, `ft/*.snippets` (UltiSnips table).
`extends` chains are loaded recursively; `_.snippets` is the all-filetype
convention (UltiSnips 'all' → the `_` special). Parse cache per file path
(mtime). Files parsed via `snippetary#parse#snippets_file(lines)`.
Merge: all snippets lists per trigger; sorted by pri desc at USE time.

### Mappings & commands

UltiSnips defaults: expand+forward `<tab>`, backward `<s-tab>` (+ <C-j>/<C-k>
as extra forward/backward). Provide:
    g:snippetary_expand_trigger (default <tab>)   — expand-or-jump
    g:snippetary_jump_forward_trigger (default <c-j>)
    g:snippetary_jump_backward_trigger (default <c-k>? snipMate uses <s-tab>)
    g:snippetary_snip_dirs = ['UltiSnips']
Plug-maps: <Plug>(snippetary-next-or-trigger), <Plug>(snippetary-back),
<Plug>(snippetary-jump), xmap <Plug>(snippetary-visual) (capture for ${VISUAL},
then `gv"_c` like snipMate).
Commands: SnippetaryReload (force re-parse files + reload buffer),
SnippetaryClean (kill active sessions), SnippetaryVersion → echo 1.0.0.
Autocmds: FileType/BufWinEnter → make sure buffer loaded; CursorMoved(I) →
live update; BufUnload → cleanup; User can disable via g:snippetary_loaded=?
etc.

### Known v1 limitations (TODO.md)

- python `!p` interpolations and `global` blocks: skipped (warn once).
- snippet transformations `${n/.../.../}` parsed but not applied (mirror).
- auto-trigger 'A', regex 'r', context 'e', prefix 'p', s/w-...-edge options:
  not implemented (r/e never match; p skipped; A/s ignored).
- multi-line mirror contents degrade to first line.
- text objects iS/aS not provided.

## Environment facts

- vader at /tmp/opencode/vader.vim, run headless:
  `vim --headless -Nu test/vimrc -c "Vader test/*.vader" -c 'qall!'`
- nvim 0.9.5: ModeChanged/TextChangedI exist; text properties DO NOT; `gh`
  and `v+C-g` enter select mode; raw-key feedkeys from `<C-R>=func()` end in
  select mode; xmap `:<C-U>call` + `normal! gv` keeps visual selection.

## Session addendum (2026-11-02 late)

Verified live after the engine build (all pass in test/*.vader):

- CursorMoved(I) DO NOT fire per keystroke in headless feedkeys runs;
  `test/vimrc` keeps the <f12> poke mapping so tests can drive
  cursor_update() manually. In real usage autocmds fire per keystroke.
- append(lnum, text) FAILS SILENTLY (returns 1) in nvim when lnum is out
  of range: the splice clamps to line('$').
- Do not redefine snippetary#* functions in probe scripts (nvim raises
  E746: name does not match script file name).
- set_line now shifts later extents from (col + oldSize) and skips the
  object being edited; cursor_update measures deltas against col('$')
  AFTER the mirror sync, shifts from (cursorcol - delta), skips the
  edited stop, then grows stop.ec and syncs mirrors.
- set_stop records prev_l/prev_d so the next user keystroke measures a
  correct delta even when no autocmd fired inside the jump.
- The user's own nvim pack can leak stale plugins into test runs
  (test/vimrc now sets packpath= to avoid it).

## Session addendum 2026-11-03 (advanced suite completion)

Advanced suite (test/advanced.vader) now green: x-option (session ends at
$0, not insert), VISUAL capture, backtick date, nested placeholder.

Root causes fixed this round:
1. parse#header rejecting "xsnip x" was test-data error; ultisnips-style
   options are packed flags ("bx"), never space separated.
2. s:untrack_nested left dead stop nums in exp.order -> E716 on jump.
3. cursor_update containment rejected the cursor at stop.ec+1, which is
   the exact position after replacing a selected stop content; session now
   survives and the subsequent jump ends it at the snippet end.
4. cursor_update returned implicit 0 through <C-R>= on empty stack, typing
   a literal "0" into the buffer; all paths now return ''.

Harness facts (headless nvim 0.9.5):
- insert mode does not survive between feedkeys(...,'xt') calls; whole
  flows must be one call (vader does this).
- <Plug> and single <f-key> <C-R>= maps fire inside batches; 2-char and
  <C-o> maps do not apply in batches.
- <C-R>= result is processed as keys, hence try_expand's "\<tab>"
  fallback inserts a real tab when the session is dead.
- After a VISUAL grab+cut the cursor sits at the cut point; expansion
  happens on the NEXT tab after typing the trigger (UltiSnips flow).

## test-config (2026-11-03)

- test-config/init.vim: throwaway manual-test nvim config. Sets rtp from
  its own script location, sets packpath= (user packs leak stale plugins
  and even hijack g:loaded_snippetary otherwise), enables filetype plugin,
  runtime-sources the plugin as belt-and-suspenders, and points
  g:snippetary_snippet_dirs at test-config/snippets.
- Start: nvim -u test-config/init.vim test-config/demo.txt
- Verified headless: hello expansion ('Hello from snippetary x!'), date
  backtick (YYYY-MM-DD), visual grab + 'wrap' expansion ('> text <'),
  each ending with session complete. (The python-block warning existed
  in 1.0.x and was removed in 1.1.1: python is skipped silently.)

## Session addendum 2026-11-03/19 (v1.1.2 - v1.3.0)

Engine changes, distilled (narrative in agent-log.md):

- goto_definition candidate order: keyword under the cursor (stitched
  from both cursor sides, multibyte-safe byte-col slicing) -> keyword
  behind the cursor -> text before cursor inclusive -> exclusive ->
  scope-file fallback. The raw probes keep multi-word triggers working
  when the cursor sits at their end.
- Block ends and directives (endsnippet/endglobal/extends/priority) are
  stripped on both ends; body lines keep raw indentation. Expansion of
  an indented-body snippet must not swallow the end line.
- UltiSnips shims (autoload/UltiSnips.vim): SnippetsInCurrentScope
  returns a SORTED LIST of {key,description} dicts - a dict would
  serialize to javascript in hash-bucket order and coc-ultisnips saw
  unordered triggers. ExpandSnippet feeds the existing <Plug> mapping.
- Splice off-by-one (v1.2.2): with buffer content below the trigger the
  last body line landed one line too low, because line('$') already
  counted the lines appended for the earlier body lines. The tail splice
  is one unconditional `append(lnum + len(nl) - 2, nl[-1] . after)`.
- !v context (v1.3.0): b:snippetary_t merges pre-rendered placeholder
  defaults (s:collect_default over the token tree) with the seen stops'
  rendered text; b:snippetary_visual exposes ${VISUAL} with \r
  stripped. String !v results insert raw; older versions string()'d
  them, wrapping values in quotes.
- nvim 0.12 regex find: the old-style pattern \C\(.+)\.[^.]+$ does NOT
  match where its \v form does; helper code uses \v forms.

User-config side (kept outside the repo): the 11 real snippet files are
converted off python (!p/global) onto !v helpers; snippet_helpers.vim
holds the vimscript ports (SnTo*Case, SnClassName*, SnFncC, SnEnum,
SnCompB, SnLcFirst, SnLcCamel, SnIf, SnSecTitle, SnHtmlSlash,
SnBase64Visual) with \C + explicit [A-Za-z0-9_] classes so the
python \w/\W semantics are immune to iskeyword/ignorecase; its vader
tests live in the user config. Parse sweep over the 37 real files:
zero errors.
