# Windows setup

Read this reference only when creating or repairing an isolated Windows Codex profile.

## Supported topology

Switchgear treats Codex CLI and VS Code as two launch surfaces for one isolated profile:

1. Keep the primary account signed in to the ChatGPT/Codex desktop app.
2. Give the secondary CLI/VS Code environment its own CODEX_HOME outside every repository and cloud-synced workspace, for example C:\Users\you\.codex-secondary.
3. Generate a CLI launcher, a VS Code launcher, or both. Each launcher sets CODEX_HOME before starting its child process.
4. Let the user complete the normal sign-in flow from that isolated environment.

OpenAI documents CODEX_HOME as the location for Codex configuration, authentication state, logs, sessions, and skills across the CLI and IDE surfaces. The directory must exist before Codex starts. A file-based credential store may be selected through config.toml; any resulting credential file is sensitive and must never be opened, copied into a repository, or shared.

Official sources:

- [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Authentication](https://learn.chatgpt.com/docs/auth)

## Before writing

Collect and repeat these exact values:

- profile label;
- new or existing isolated CODEX_HOME;
- workspace to open;
- targets: CLI, VSCode, or both;
- Codex CLI executable when CLI is selected and automatic discovery is insufficient;
- VS Code executable when VSCode is selected and automatic discovery is insufficient;
- output directory for generated launchers;
- whether a new empty profile may receive a minimal config.toml.

Confirm that the user authorizes those exact writes. Permission to create launchers is not permission to edit an existing profile, workspace, desktop configuration, authentication state, or PATH.

## Existing-profile preflight

When the profile is already registered, run:

~~~powershell
switchgear doctor B
~~~

Resolve failures before replacement. Running VS Code is a warning during inspection, but every Code.exe process must exit before a VS Code profile switch. CLI-only use does not require closing VS Code.

## Interactive setup

For the supported dual-account flow, run:

~~~powershell
switchgear setup
~~~

The user chooses CLI, VS Code, or both and whether to create a desktop shortcut. Three-account setup is intentionally unavailable until the dual-account flow has passed real-world validation.

## Non-interactive preview

Preview an exact setup before writing:

~~~powershell
switchgear setup B -Mode Dual -Targets Both -DefaultTarget CLI -CodexHome "C:\Users\you\.codex-secondary" -Workspace "D:\projects\shared-workspace" -DesktopShortcut VSCode -WhatIf
~~~

After reviewing the plan and obtaining explicit approval, repeat without WhatIf.

Depending on the selected options, Switchgear may create:

- the isolated profile directory, if absent;
- a minimal config.toml only when the file is absent and ConfigureFileCredentialStore is requested;
- Switchgear-{Profile}-CLI.cmd;
- Switchgear-{Profile}-VSCode.cmd.
- a desktop shortcut for a selected surface;
- a local state.json containing paths, targets, and launcher metadata only.

Switchgear preserves an existing config.toml. Force only permits replacing generated launchers, shortcuts, and non-secret Profile metadata; it never authorizes overwriting profile configuration.

## CLI use

The CLI launcher:

- sets process-local CODEX_HOME;
- enters the chosen workspace;
- starts Codex and forwards every argument.

Examples:

~~~powershell
switchgear B cli
switchgear B cli exec "summarize this repository"
~~~

Do not use the generated test examples against a real profile until the user has reviewed the exact paths.

## VS Code use

1. Close every VS Code window and wait for all Code.exe processes to exit.
2. Run switchgear B vscode or double-click the generated shortcut.
3. Complete the normal sign-in flow if prompted.
4. Confirm the intended account in the Codex profile UI. A login-status command alone does not prove account identity.
5. In a new integrated terminal, print only the CODEX_HOME path if verification is needed.

## Switching or repairing

- CLI launchers are independent terminal processes and do not require a VS Code shutdown.
- Close all VS Code windows before using a VS Code launcher for another profile.
- If the wrong account appears, close that surface and relaunch the intended profile. Never copy credentials between profiles.
- If an existing config.toml lacks the desired credential-store setting, report the discrepancy and ask for a narrowly scoped decision. Do not overwrite it.
- Never delete a profile to solve an account mismatch. Preserve it and diagnose paths and process state first.
