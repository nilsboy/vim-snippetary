- [x] add SnippetaryEdit/SnippetaryEditGlobal commands, a goto_definition
      helper and the all.snippets all-filetypes alias
- [x] drop the python-skip warnings (file load and expand time)
- [x] goto_definition: word under the cursor, else the word behind it
- [x] block ends and directives tolerate leading indentation
      (endsnippet/endglobal/extends/priority written indented)
- [x] coc-ultisnips integration: UltiSnips-API shims backed by snippetary
      (popup triggers via coc, expansion stays snippetary)
- [x] coc popup: snippet items arrive in a stable alphabetical order
- [x] splice: multi-line expansion keeps lines below the trigger below
      the snippet (tail-append off-by-one)
- [x] t[n] context for !v interpolations (b:snippetary_t with preset
      defaults + rendered-so-far, b:snippetary_visual) - python t[] analog
- [x] create a classic vimscript snippets plugin that works with ultisnips
      snippets
- [x] test everything with vader
- [x] investigate: plugin/snippetary.vim not sourced by `filetype plugin on`
      in test harness (rtp ok); workaround: source explicitly. Answer:
      plugin/ scripts load only during the startup phase; `filetype plugin
      on` merely installs autocmds, and with -Nu NONE nothing sources the
      plugin, so test/vimrc keeps the explicit source.
- [x] add vim help doc
- [x] test all mappings with vader

- [x] regex ('r') snippets: python-re subset matcher (finditer +
      end-at-cursor semantics, groups -> b:snippetary_match for !v),
      corpus-driven tests
