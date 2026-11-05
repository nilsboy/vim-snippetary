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
