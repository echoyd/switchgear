# Switchgear v0.1.0

First public Windows release: a local profile manager for a second Codex environment in CLI, VS Code, or both.

Download `Switchgear-0.1.0-windows-x64.zip`, verify its SHA-256 against `SHA256SUMS.txt`, extract it, and double-click `START-HERE.cmd`. The package contains readable CMD/PowerShell scripts. It requires Windows x64 with Windows PowerShell 5.1, plus separately installed Codex CLI and/or VS Code with the Codex extension. It is not a standalone EXE and does not bundle Codex or VS Code.

Highlights:

- Guided dual-account setup, optional desktop shortcut, `list`, `doctor`, and CLI argument forwarding.
- Isolated CODEX_HOME for the secondary profile; no credential copying or account-limit pooling.
- User-local installer with preview, update, and conservative uninstall. Uninstall preserves profile data by default.
- Companion `profile-switchgear` Skill included as source, not installed automatically.

Validation: PowerShell syntax, temp-only setup and install/update/uninstall tests, Skill validation, and a real Codex CLI invocation from a fresh unauthenticated temporary profile. The underlying A/B workflow has been used with real accounts; this packaged build has not performed an automated real-account sign-in or a separate-machine test. Users complete login themselves and verify the active account in Codex.

This is an independent community tool, not an OpenAI product. See README and SECURITY before use.
