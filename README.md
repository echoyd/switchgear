# Switchgear

> Switch profiles. Keep credentials isolated.

Switchgear is an open-source Windows profile manager for Codex CLI and VS Code. Its core command creates isolated launchers, stores non-secret Profile metadata, opens the requested surface, and runs health checks. A companion Codex Skill provides guided setup and troubleshooting. It is not affiliated with or endorsed by OpenAI.

The first supported topology keeps account A in the ChatGPT/Codex desktop app and launches account B through its own CODEX_HOME. CLI and VS Code are equal entry points into B.

## Download and start

1. Download `Switchgear-0.1.0-windows-x64.zip` from GitHub Releases and extract it to a normal folder. Do not run scripts from a ZIP preview.
2. Install [Codex CLI](https://learn.chatgpt.com/docs/codex/cli) if you want CLI use. Install [Visual Studio Code](https://code.visualstudio.com/) and its Codex extension if you want VS Code use. Switchgear bundles neither program.
3. Double-click `START-HERE.cmd`. The installer shows its target paths and asks before installing. The setup wizard then asks for CLI, VS Code, or both, a workspace, and an optional desktop shortcut.
4. Sign in to the second account yourself in the launched CLI or VS Code extension. Confirm the intended account in the product UI; `codex login status` alone does not identify it.

Requires Windows x64 and Windows PowerShell 5.1. No administrator rights or separate PowerShell install are needed. This package contains readable PowerShell and CMD scripts, not a standalone EXE. Review the source and SHA-256 checksum before running downloaded scripts; do not disable system security protections.

For portable use without installing Switchgear or changing the user `PATH`, open a terminal in the extracted directory and run `switchgear.cmd setup` directly. Choose a desktop shortcut during setup for easy daily access.

## What it does

- guides the user through a dual-account setup;
- creates CLI-only, VS Code-only, or combined profiles;
- creates an optional desktop shortcut;
- supports switchgear B, switchgear B cli, and switchgear B vscode;
- forwards ordinary Codex CLI arguments, including exec;
- stores only Profile labels, paths, targets, and launcher locations;
- checks profile isolation and blocks unsafe VS Code process reuse.

## What it does not do

- copy, read, or compare credentials;
- automate account login;
- share an account between people;
- merge subscriptions or usage limits;
- bypass OpenAI plan limits;
- change the account used by the ChatGPT/Codex desktop app;
- enable three-account setup before the dual-account flow is stable.

## Command-line setup

Show the command help:

~~~powershell
.\switchgear.cmd help
~~~

Start the guided dual-account setup:

~~~powershell
.\switchgear.cmd setup
~~~

Preview the user-local installer without writing anything:

~~~powershell
.\install-switchgear.cmd -WhatIf
~~~

Installer defaults:

- program files: `%LOCALAPPDATA%\Programs\Switchgear`;
- command access: adds that program directory to the current user's `PATH`;
- Profile data: `%LOCALAPPDATA%\Switchgear`, kept outside the program directory;
- uninstall: removes program files and its PATH entry, but preserves Profile data.

Development tests pass `-SkipPathRegistration` and use random system-temp directories, so they do not install Switchgear or alter the real user PATH.

After a real installation, update and uninstall use the same explicit lifecycle:

~~~powershell
.\install-switchgear.cmd -Update
.\uninstall-switchgear.cmd
~~~

An update refuses to change the registered Profile data directory. The uninstaller removes a PATH entry only when the installer originally added it.
For non-interactive use through the CMD wrappers, pass `-Yes`; PowerShell callers may also use the standard confirmation controls directly.
The installed CMD uninstaller uses a marked two-stage cleanup so it can exit normally before deleting its final command entry.

Preview an exact configuration without writing:

~~~powershell
.\switchgear.cmd setup B -Mode Dual -Targets Both -DefaultTarget CLI -CodexHome C:\Users\you\.codex-secondary -Workspace D:\projects\demo -DesktopShortcut VSCode -WhatIf
~~~

After setup:

~~~powershell
switchgear B
switchgear B cli
switchgear B cli exec "summarize this repository"
switchgear B vscode
switchgear list
switchgear doctor B
~~~

## Project layout

- core/: the standalone local command and deterministic engines.
- skill/profile-switchgear/: the companion workflow Skill.
- docs/CLI-UX.md: the approved terminal interaction baseline.
- tests/smoke.ps1: isolated end-to-end tests.
- installer/: user-local install, update, and conservative uninstall lifecycle.
- tests/installer-smoke.ps1: temp-only installer lifecycle tests.
- tests/installer-safety.ps1: destructive-boundary tests using disposable temp data only.

## Scope and verification

v0.1.0 supports one managed secondary profile on Windows. Its state schema uses a Profile list so a future three-account version can extend the product without redesigning the core format.

The workflow is based on an existing real two-account Windows setup. The Switchgear package itself has passed PowerShell parsing, Skill validation, temp-only setup/install/update/uninstall tests, and a real Codex CLI invocation with a fresh isolated, unauthenticated CODEX_HOME. This release does not claim an automated real-account sign-in test or a separate-machine test; each user completes and verifies their own sign-in.

Switchgear does not bundle Codex CLI, VS Code, or the Codex extension. It does not automatically install the companion Skill. Keep every CODEX_HOME outside repositories and synced/shared workspaces. See [SECURITY.md](SECURITY.md) and the [MIT license](LICENSE).

OpenAI documents CODEX_HOME as the root used by Codex CLI, the IDE extension, app-server, and installers. See [environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables), [Codex CLI](https://learn.chatgpt.com/docs/codex/cli), and [authentication](https://learn.chatgpt.com/docs/auth).
