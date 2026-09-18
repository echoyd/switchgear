# Shared workspace and handoff

Read this reference when two isolated Codex environments will work with the same project files.

## Architecture

Keep two kinds of state separate:

- **private environment state:** authentication, sessions, configuration, logs, usage, and account-level memory stay in each profile;
- **project state:** source code, project instructions, decisions, tests, acceptance evidence, and Git history live in the formal project directory.

Never place a `CODEX_HOME` inside the repository or a cloud-synced shared folder. Never add it to `.vscode/settings.json`.

## Start-of-task check

Before either environment writes:

1. identify the active Codex surface and profile;
2. confirm the current task directory and formal project root;
3. read the applicable `AGENTS.md` and project handoff file;
4. inspect the branch, HEAD, and working-tree changes;
5. determine whether another writer is active;
6. agree on exact file scope and final storage location.

Treat uncommitted changes as belonging to their current owner unless the handoff says otherwise. Do not reset, clean, or fold them into a new commit.

## Concurrency rule

- Different projects: both environments may work at the same time.
- Same project, same working directory: work sequentially and hand off explicitly.
- Same project in parallel: use real Git worktrees or isolated branches and non-overlapping file scopes.
- No Git repository: one writer at a time.

Git worktrees are the preferred isolation mechanism when genuine parallel work is required. Verify the current official workflow before creating one: <https://learn.chatgpt.com/docs/environments/git-worktrees>.

## Handoff protocol

The outgoing environment should stop editing, then record:

- objective and current state;
- files changed;
- checks completed and their results;
- known risks or unresolved questions;
- exact next action;
- branch and commit, or an explicit statement that changes are uncommitted.

The receiving environment performs a read-only comparison of the handoff against the actual files and Git state before writing. If they disagree, both writers stop until the conflict is resolved.

Use `assets/templates/AGENTS.template.md` and `assets/templates/PROJECT_HANDOFF.template.md` as starting points. Replace every placeholder with project-specific facts; do not copy credentials or local account identifiers into either file.
