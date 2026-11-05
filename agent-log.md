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
