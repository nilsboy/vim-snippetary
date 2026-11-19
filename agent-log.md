# agent-log — vim-snippetary session notes

## Status (2026-11-02, work in progress)

What exists and works:
- `autoload/snippetary/parse.vim`: ULTISNIPS file/body parser (verified by
  probes: nested placeholders, bare mirrors, transform/choice degradation,
  escapes, header quirks).
- `autoload/snippetary.vim`: engine state, UltiSnips-compatible trigger
  matching (default/w/i/b, skip r/e), tabs_to_indent + body_prep (recovered
  UltiSnips launch() indent rule verbatim), render walker (open pile),
  absolute stop conversion, order walk, session removal, live mirror sync
  helpers, mapping entry points, GrabVisual.
- `plugin/snippetary.vim`: settings, Plug maps (snipMate-style C-R=), commands
  SnippetaryReload/Clean/Version, autocommands.
- `NOTES.md`: full design document. `test/vimrc` + `test/smoke.vader`
  functional (vader runs headless: `vim --headless -Nu test/vimrc -c "Vader!
  test/smoke.vader" -c 'exe get(get(g:,"vader_result",{}),"successful",0) ?
  "qa!" : "cq"'`).

Open issues (next steps, in order):
1. Post-expansion flow lands in normal mode. The expansion via real `<tab>`
   mapping produces correct buffer text ('if :' + second line with indent) and
   a correct session (stops at abs positions), but after the mapping the
   editor is in normal mode; typed text then goes to the wrong column.
   Probe evidence: C-R= entry mode=i; EXP stops correct; the splice uses
   `setline`/`append` with correct math. Hypotheses:
   a. The returned '' from an empty first stop leaves the mapping
      terminated with insert dropped — snipMate never returns '' for stops:
      maybe the C-R= context needs an explicit re-entry (e.g. the snoremap
      variant uses `<Esc>a`); for imap the empty return should keep insert.
   b. The `append()` calls inside C-R= evaluation cancel the pending
      insert-mode cursor state (buffer changed under the cursor).
   c. The foldopen + undolevels tricks interact.
   Debug approach: single feedkeys call, diag writefiles INSIDE the engine
   between splice steps, assert `mode()` at each step (use the real plugin,
   no redefinitions - nvim E746 blocks redefining snippetary#* in scripts).
2. Then verify select-mode entry for non-empty first stop (fn snippet).
3. Then jump forward/backward + mirrors live sync + wrap/exit + 'x' option.
4. Full vader suite (parser, matching, expansion, jumps, mirrors, options,
   file-loading incl. a slice of the vim-snippets corpus).
5. Project files: README, .gitignore (dist/, tmp/), version 1.0.0, TODO.md
   checkboxes, keep AGENTS.md rules (nothing to do there).

Design facts to keep (from NOTES.md):
- Matching: before-cursor words vs trigger with option semantics.
- Stop = absolute (line, byte-col) extent, end EXCLUSIVE; mirrors same-line.
- Live update = col('$') delta on CursorMovedI; untrack nested on change;
  shift same-line later tracks; remove session when cursor leaves stop.
- Wrap-cycle jumps like snipMate; 0 = exit stop, placed last in order.
- No sentinels ever: any exit path leaves the buffer text as-is.

Constraints discovered empirically (nvim 0.9.5 headless):
- Vim slices inclusive; negative single-index string access returns ''.
- `<C-R>=` + returned keystroke strings end in select mode when designed so.
- `exists('*autoload#fn')` = 0 before the first call: not an error.
- E746: cannot define snippetary#* functions outside their autoload file in a
  probe script.
- feedkeys('x') executes and returns; insert mode does not survive ACROSS
  feedkeys calls in headless scripts, so tests must feed whole sequences in
  one call or use vader Do blocks.

Session limitation: my reasoning repeatedly collapsed into degenerate symbol
repetitions; all analysis after that point must be done in short bursts with
verification via probes/tests.
## 2026-11-03 advanced suite green

- header("xsnip \"x\" b x") failing was TEST DATA error: options must be a
  packed flag string ("bx"), parse correctly errors like UltiSnips.
- Engine fixes: s:untrack_nested now cleans exp.order (E716 stops[2]);
  cursor_update early-path returns '' (implicit 0 was inserted by <C-R>=);
  containment accepts cc == stop.ec + 1 (cursor on the end boundary after a
  full-selection replacement no longer kills the session).
- Harness facts: in feedkeys('xt') batches insert mode only persists inside
  one call; <Plug>/<f-key> <C-R>= maps fire inside batches; 2-char maps and
  <C-o> maps do NOT; f12 probes proved expansion/jump/end-session timeline.
- Test-flow truths (UltiSnips semantics): VISUAL flow is select -> tab
  (grab+cut) -> type trigger -> tab (expands with ${VISUAL}); overwriting a
  tabstop with defaults destroys nested stops; jumping past last tabstop ends
  session; final <tab> on dead session inserts a literal tab.
- Full suite now 27/27 cases, 50/50 assertions; version bumped to 1.0.1.

## 2026-11-03 edit/goto feature + all.snippets alias (v1.1.0)

- New: :SnippetaryEdit [scope], :SnippetaryEditGlobal and normal-mode
  snippetary#goto_definition() (jump to the defining file's `snippet`
  header line, fallback to the scope's file). parse#snippets_file now
  records the 1-based header line per snippet ('head'); load_buffer keeps
  'path'/'line' per merged trigger. A BufWritePost hook re-parses on
  .snippets/.snippet saves.
- for_scope('_') now also matches all.snippets / all_*.snippets / all/
  (legacy UltiSnips naming), and all results are deduped (the '_*.snippets'
  glob used to match _.snippets twice). edit_target returns the first
  existing file for the scope or a creation path in the first configured
  directory (fallback base = first runtimepath entry for unresolved
  relative dir names).
- test/vimrc made portable: runtimepath root derived from <script>, vader
  dir resolved from $SNIPPETARY_TEST_VADER, then /tmp/opencode/vader.vim,
  then the user config checkout.
- New suite test/edit.vader (8 cases): covers dedupe, native-over-alias
  edit order, open-existing vs create-in-primary-dir, EditGlobal with both
  conventions, goto to ft/all.snippets files line-accurate, and the
  no-match file fallback.
- Harness note (nvim 0.12.6): a test After block running `bwipeout!` fully
  unloads the vader workbench buffer; the next case then fails with E86 in
  vader#window#prepare. The vader copy at /tmp/opencode/vader.vim is
  patched in s:switch_to_workbench to recreate a vanished workbench buffer
  instead of raising E86. Same patch should be re-applied when the vader
  checkout is refreshed; nvim 0.9.5 is not affected either way.
- Old-suite external fixtures (/tmp/opencode/{vader,jump,match,adv,
  corpus}_snips) were missing in the fresh environment and have been
  reconstructed from the suite expectations; the corpus dir gets the
  UltiSnips/*.snippets files of a honza/vim-snippets clone. Full suite:
  35/35 cases, 64/64 assertions, version 1.1.0.

## 2026-11-03 warnings removed (v1.1.1)

- Per request, python-skip notices are gone entirely: file#read no longer
  echoms the load-time warning, the engine's s:warn_python (expand-time,
  session-flagged) is deleted along with the now-dead 'pywarn' session
  key. Python content still degrades silently (blank/omitted).
- Docs adjusted (README limitation bullet, doc syntax section, NOTES
  addendum); version 1.1.1.

## 2026-11-03 goto uses the cursor word (v1.1.2)

- [v1.2.3/1.3.0 addition] engine: expand-time t[n] context for !v —
  b:snippetary_t holds each stop's text (presets from the token tree for
  pending stops, rendered text for closed ones) and b:snippetary_visual
  holds the captured ${VISUAL} text; !v string results insert raw (the
  old string() wrapped strings in quotes - changed, matches UltiSnips).
- [v1.3.0 addition] config: snippet_helpers.vim (vimscript ports of the
  python helpers: SnTo*Case, SnClassName*, SnFncC, SnEnum, SnCompB,
  SnLcFirst, SnLcCamel, SnIf, SnSecTitle, SnHtmlSlash, SnBase64Visual)
  + vader tests (/home/ai/.config/nvim/test/); all regexes use \C and
  explicit [A-Za-z0-9_] classes: python \w/\W semantics, immune to the
  user's iskeyword/ignorecase settings. Notable nvim 0.12 find: the
  old-style pattern \C\(.+)\.[^.]+$ does NOT match while its \v form
  does — all helper regexes use \v.
- [v1.3.0 addition] user snippets: all 11 files converted off python
  (!p/global) onto !v helpers and enumerated w-triggers; parse sweep
  shows zero invalid lines; expansions verified headless (js import/
  new/class, ts class, html span./span#/form/title, vim command,
  mongodb join, swagger verb, help sec/ssec, all toggles).
- goto_definition now picks the KEYWORD UNDER THE CURSOR (run stitched
  from both sides of the cursor char; byte-col slicing stays on char
  boundaries, multibyte-safe); when the cursor is not on a keyword it
  uses the last word behind the cursor (words_for_line over the text up
  to the cursor position - same expression works for insert-mode
  positions).
- The old raw-text probes are kept as tertiary candidates so multi-word
  triggers still jump when the cursor sits at their end. Match order:
  cursor word -> behind word -> text before cursor (inclusive) -> text
  before cursor (exclusive) -> file-level fallback.
- test/edit.vader: +2 cases (mid-word 'x sec' cursor on 's' opens the
  definition header line, non-keyword cursor '-' falls through to the
  word behind).

## 2026-11-03 indented block ends (v1.1.3)

- Bugfix: `endsnippet` / `endglobal` with leading indentation and
  directives written indented were not recognized: the trailing-only
  rstrip compare swallowed `  endsnippet` into the body, so such snippets
  expanded one extra body line. parse#snippets_file now strips both ends
  for block ends (UltiSnips line.strip() semantics) and derives directive
  heads from the stripped line; body lines keep their raw indentation.
- test/edit.vader: +3 cases (indented endsnippet body, indented endglobal
  + extends, full expansion of the user's space-indented if snippet with
  ${VISUAL}$0 -> exactly 3 lines, one body line between the braces).

## 2026-11-03 coc-ultisnips via UltiSnips shims (v1.2.0)

- autoload/UltiSnips.vim: shims so the installed coc-ultisnips extension
  uses snippetary as its engine: SnippetsInCurrentScope returns the
  merged buffer triggers ({trigger: description} dict form the extension
  accepts) incl. the all-filetypes scope; ExpandSnippet feeds the
  existing <Plug>(snippetary-next-or-trigger) to expand the trigger the
  popup accepted. plugin/snippetary.vim announces
  g:did_plugin_ultisnips = 1 only when the real UltiSnips has not. Drop
  the shim file when re-enabling real UltiSnips (note in the file).
- coc popup now contains snippet triggers merged with language-server
  items; accepting expands via snippetary mirrors/${VISUAL}; the typed
  trigger <tab> flow is unchanged.
- test/edit.vader: +2 cases (shim data incl. descriptions and the '_'
  scope; expansion through the shim from an insert accept position).
  Full suite: 42/42 cases, 79/79 assertions. Version 1.2.0.

## 2026-11-03 splice off-by-one mid-buffer (v1.2.2)

- Bugfix: expanding a multi-line body with content BELOW the trigger line
  misplaced the last body line one line too low (append used
  `lnum + len(nl) - 1` while `line('$')` already included the
  `len(nl) - 2` lines appended just before, so the final `append()`
  landed after the first following line instead of the snippet's last
  body line). The tail splice is now a single unconditional
  `append(lnum + len(nl) - 2, nl[-1] . after)` - correct mid-buffer and
  identical to the old end-of-buffer behavior.
- test/edit.vader: +2 cases (3-line body expanded on line 1 of
  if/a/b -> if() {}, $0 line, }, a, b; 2-line body mid-buffer). Full
  suite: 44/44 cases, 91/91 assertions. Version 1.2.2.

## 2026-11-03 popup item order (v1.2.1)

- UltiSnips#SnippetsInCurrentScope now returns a SORTED LIST of
  {key, description} dicts instead of an unsorted dict: vim Dictionaries
  serialize to javascript in hash-bucket order, so coc-ultisnips saw the
  triggers unordered (its extension already accepts both shapes; the list
  branch preserves order). Sort is alphabetical, case-insensitive.
- test/edit.vader: shim case now asserts the exact order alltrig →
  globtrig → hdr → sec. Version 1.2.1.
