# vim-snippetary

A pure-vimscript snippet engine for Vim/Neovim that reads **UltiSnips
snippet files**. No Python: everything is classic `:h vimscript` so it
works in any build that supports `autoload`, including the stripped-down
`vim.tiny`-class binaries people ship on servers.

## Install

Copy this directory into your runtime path (or add it as a plugin):

    git clone <repo> ~/.config/nvim/plugged/vim-snippetary
    set runtimepath^=~/.config/nvim/plugged/vim-snippetary

## Configuration

Nothing is required. Defaults mirror UltiSnips:

    let g:snippetary_expand_trigger = '<tab>'
    let g:snippetary_jump_backward_trigger = '<s-tab>'
    let g:snippetary_snippet_dirs = ['UltiSnips']

Snippet files are discovered in `g:snippetary_snippet_dirs` directories on
the runtimepath: `ft.snippets`, `ft_*.snippets`, `ft/*.snippets` and the
`_`-prefixed file applies to every filetype, like UltiSnips. The legacy
naming `all.snippets` / `all_*.snippets` / `all/` is honored for the
all-filetypes scope too (native `_.snippets` wins on conflict).
`extends`, `priority` and quoted multi-word trigger headers are honored;
`.snippets` files get `filetype=snippets` for editing and a reload fires
when they are written.

## Mappings

Snippet files live in `g:snippetary_snippet_dirs` (see below) on the
runtimepath: `ft.snippets`, `ft_*.snippets`, `ft/*.snippets` and the
`_`-prefixed file applies to every filetype (its legacy `all.*` names
are honored as well). `extends`, `priority` and quoted multi-word
trigger headers are honored; `.snippets` files get `filetype=snippets`.
`<Plug>(snippetary-next-or-trigger)`, `<Plug>(snippetary-back)` and
`<Plug>(snippetary-visual)` exist for custom keys.

## Commands

    :SnippetaryReload   reread snippet files
    :SnippetaryClean    end every running snippet session in the buffer
    :SnippetaryVersion  print version (SemVer)
    :SnippetaryEdit [scope]
                        open the snippet file of a scope (default: the
                        buffer's first filetype); creates it in the first
                        configured directory on write when missing
    :SnippetaryEditGlobal
                        open the all-filetypes snippet file

Normal-mode helper for mappings: `snippetary#goto_definition()` jumps to
the file and `snippet` header line of the snippet for the keyword under
the cursor (the last word before the cursor when the cursor is not on a
keyword), falling back to the filetype's snippet file. Snippet files are
reloaded automatically after a write.

## Behavior notes

* Tabstops/mirrors are tracked as (line, col) bookkeeping, not sentinel
  characters: leaving a snippet through any path leaves clean text.
* Typing inside a tabstop updates mirrors live while the cursor stays in
  the stop; editing outside ends the session.
* `${VISUAL}` captures the last visual selection once: selecting text and
  pressing the expand key grabs the selection, cuts it and drops you in
  insert; typing a trigger and pressing the expand key again expands the
  snippet with `${VISUAL}` filled from the cut text, like UltiSnips.
* Overwriting a tabstop's content destroys tabstops nested inside it.
* Jumping past the last tabstop ends the session and leaves the cursor
  at the end of the snippet.
* Backtick shell interpolation runs the command and embeds the output.
* Python interpolation (`!p`, `global !p`) is skipped; the snippet text
  still expands.
* Transforms and choice lists of UltiSnips degrade gracefully (transform →
  plain mirror, choice → first choice).

## coc-ultisnips integration

`autoload/UltiSnips.vim` provides UltiSnips-API shims
(`UltiSnips#SnippetsInCurrentScope`, `UltiSnips#ExpandSnippet`) backed by
snippetary, and the plugin announces `g:did_plugin_ultisnips` (only when
the real UltiSnips has not). The installed coc-ultisnips extension then
serves the buffer's triggers inside the coc completion popup (merged
with the language-server items, filtered as you type) and expanding an
accepted snippet runs through snippetary - expansion, mirrors and
`${VISUAL}` all stay snippetary behavior. When the real UltiSnips is
re-enabled, delete the shim file so its own autoload wins.

## Testing

The test suite uses vader.vim (see `test/`); current status
**(44/44 cases, 91/91 assertions)** across seven suites (smoke, parse,
jumps, match, corpus, advanced, edit). Headless runs cannot fire
`CursorUpdated`-style autocmds per keystroke, so `test/vimrc` defines an
`<f12>` hook that invokes `snippetary#cursor_update()` inside batches.

    vim --headless -Nu test/vimrc -c 'Vader! test/*.vader' -c 'exe
    get(get(g:,"vader_result",{}),"successful",0) ? "qa!" : "cq"'

For playing with the plugin interactively there is a throwaway config in
`test-config/` (isolated from your own setup via `packpath=`):

    nvim -u test-config/init.vim test-config/demo.txt

It ships demo snippets in `test-config/snippets/_.snippets`: try
`hello<tab>`, `date<tab>`, or select text, `<tab>`, then `wrap<tab>`.

## License

MIT-style; snippet files remain under their upstream licenses (this repo
is tested against honza/vim-snippets files).
