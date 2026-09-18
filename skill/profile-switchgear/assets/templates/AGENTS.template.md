# Project collaboration rules

## Source of truth

- Formal project root: `{{FORMAL_PROJECT_ROOT}}`
- Project instructions, source, tests, and acceptance evidence live under this root.
- Temporary chat folders and profile directories are not formal delivery locations.

## Environment separation

- Codex profiles share project files only.
- Authentication, sessions, usage, logs, and account configuration remain private to each profile.
- Never copy or commit credentials, cookies, tokens, or session databases.
- Never set `CODEX_HOME` in this repository's `.vscode/settings.json`.

## Editing and Git

- Check the branch and working tree before editing.
- Use one writer at a time in a shared working directory.
- For parallel work, use separate Git worktrees or agreed non-overlapping branches and file scopes.
- Do not reset, clean, amend, force-push, publish, or upload without explicit authorization.
- Commit only a complete, checked stage and stage only files in the approved scope.

## Handoff

- Read `PROJECT_HANDOFF.md` before taking over work.
- The outgoing environment stops editing before updating the handoff.
- The receiving environment verifies the handoff against the actual files before writing.
- On any mismatch or overlap, preserve the current state and stop both writers.
