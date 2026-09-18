---
name: profile-switchgear
description: Guide users through Switchgear setup, inspection, or repair for isolated Codex CLI and VS Code profiles on Windows. Use for multi-account profile selection, launcher creation, health checks, or safe project handoff after the Switchgear core command is available. Do not use to share accounts, combine quotas, bypass plan limits, or copy credentials.
---

# Switchgear

Switch profiles. Keep credentials isolated.

Act as the safe workflow layer around the local Switchgear command. Keep Codex authentication environments separate while allowing them to collaborate through ordinary project files and Git. The validated Windows topology is:

- one account in the ChatGPT/Codex desktop app;
- another account in Codex CLI, VS Code, or both, launched with an isolated CODEX_HOME;
- an optional shared project workspace that contains no credentials.

Treat CLI and VS Code as equal entry points into the same isolated profile. The desktop app is a separate surface; never claim that changing CODEX_HOME switches or isolates its authentication.

## Choose the mode

- **Inspect or troubleshoot:** run switchgear doctor for the requested profile and explain only its sanitized checks. This mode is read-only.
- **Create a secondary profile:** read [Windows setup](references/windows-setup.md), state every target path and selected surface, obtain explicit authorization for those writes, preview with WhatIf, then run switchgear setup.
- **Set up project collaboration:** read [workspace handoff](references/workspace-handoff.md) and adapt the templates in assets/templates to the user's repository.
- **Repair:** diagnose first. Change only the exact launcher or non-secret configuration the user authorizes. Never delete a profile as a repair shortcut.

If the Switchgear command is missing, report that the core product is not installed and provide its verified local installation route. Do not recreate setup logic ad hoc inside the Skill.

On macOS or Linux, explain that this release has only been validated for Windows. Do not run the Windows core or present an untested translation as verified.

## Required safety boundaries

- Never request, open, print, copy, compare, move, or synchronize auth files, access tokens, cookies, passwords, session databases, or OS credential-store entries.
- Each account must be controlled and authenticated interactively by its legitimate user. Do not automate browser login or facilitate account sharing.
- Never describe separate accounts as one quota pool or promise doubled, unlimited, or bypassed usage. Entitlements and limits remain separate.
- Keep every CODEX_HOME outside repositories and shared or cloud-synced workspaces. The profile and workspace must not contain one another.
- Do not set CODEX_HOME in a repository's .vscode/settings.json. Account selection belongs to the launcher process environment.
- The Codex CLI and IDE extension can use the same profile state under one CODEX_HOME. Warn that file-based credentials are sensitive without inspecting them.
- The command codex login status confirms whether authentication works, not which human account is active. Ask the user to confirm the intended account in the product UI.
- Require all Code.exe processes to exit before launching a different VS Code profile. This restriction does not apply to the CLI launcher. The ChatGPT/Codex desktop app may remain open.
- Same repository and same working directory means one writer at a time. For genuine parallel work, use separate Git worktrees or clearly isolated branches and file scopes.
- Never modify authentication, launchers, shortcuts, configuration, Git state, or shared workspace files without authorization for the exact targets.

## Inspection workflow

1. Establish the Windows version, selected targets, isolated CODEX_HOME, workspace, executable paths, and whether VS Code is already running.
2. Run a target-specific check, for example:

   ~~~powershell
   switchgear doctor B
   ~~~

3. Treat a missing profile directory, overlapping workspace, workspace-level CODEX_HOME setting, or missing executable for a selected target as a failure.
4. Treat running VS Code, absent profile-local configuration, skipped authentication, or an unconfirmed account identity as warnings that require explanation.
5. Report only paths, configuration presence, target availability, and PASS/WARN/FAIL results. Do not expose account identifiers or authentication material.

## Setup completion criteria

A setup is complete only when:

- the profile and workspace do not overlap;
- Switchgear state contains only non-secret Profile metadata;
- each generated launcher sets CODEX_HOME only for its child process;
- the CLI launcher enters the selected workspace and forwards all Codex arguments;
- the VS Code launcher refuses to start while Code.exe is already running;
- a requested minimal credential-store configuration was created only for a new config, or an existing config was preserved;
- the user completed normal sign-in themselves and confirmed the intended account;
- the target-specific health check has no failures;
- any shared repository has an explicit handoff and concurrent-editing rule.

Use current official documentation when behavior may have changed:

- [Environment variables](https://learn.chatgpt.com/docs/config-file/environment-variables)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Authentication](https://learn.chatgpt.com/docs/auth)
- [Skills](https://learn.chatgpt.com/docs/build-skills)
- [Git worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees)
