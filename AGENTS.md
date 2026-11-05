# AGENTS.md

## Rules

- Don't touch this file
- Wrap markdown files at 80 characters
- Write your thoughts into agent-log.md
- Maintain a agent-exe-log.md with timestamps to protocoll every command that is being executed in the shell
  - to be able to recover from a crash
  - write the file before execution
  - write it again after execution adding the exit code
- Put your notes/documentation into NOTES.md
- Keep README.md current
- Use SemVer versioning and start at 1.0.0 and update on every build
- Add or update tests
- TODOs are stored in TODO.md
- When given TODOs outside of TODO.md, add them to TODO.md immediately
- Before touching TODO.md reread it to prevent external changes from deletion
- When finishing a TODO immediately prefix it with '- [x] '
- When all TODOs are done check if new ones where added to the file
- Read additional project instructions from PROJECT.md if it exists. Don't change this file.
- Put final binaries into dist/ in project directory - but gitignore them
- Use ./tmp/ in project directory for tempfiles - but gitignore them

## Code Style

- Use descriptive names; avoid unnecessary comments.

