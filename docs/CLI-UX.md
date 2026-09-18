# Switchgear CLI 体验基线

## 定位

Switchgear 是面向 Windows Codex 多账号用户的本地 Profile 管理与启动工具。首版只解决一个高频问题：保留账号 A 的 Codex 桌面端，同时让账号 B 稳定进入 CLI、VS Code 或两者。

## 产品约束

- 主要用户：使用多个本人可控 Codex 账号的 Windows 开发者与高级用户。
- 运行环境：Windows 10/11、Windows PowerShell 5.1 或更高版本。
- 联网边界：配置、检查和启动器生成可离线；Codex 登录本身按官方流程联网并由用户操作。
- 系统集成：只使用本地文件、进程检测和可选桌面快捷方式；不连接外部服务。
- 平台范围：v1 仅 Windows；不承诺 macOS 或 Linux。
- 优先级：账号隔离与可恢复性高于动画和装饰；日常操作必须短。
- 数据位置：非敏感状态默认位于 LocalAppData\Switchgear；Codex 认证状态保存在各自独立的 CODEX_HOME。
- 日常入口：switchgear 命令或桌面快捷方式。
- 更新方式：开发阶段从源码运行；用户级安装器采用带安装标记的受控更新，Profile 数据保存在程序目录之外；正式发布包仍需单独版本化和验收。
- 验收证据：临时空目录端到端测试、真实终端截图、错误与空状态检查，不以“脚本能运行”代替体验验收。

## 首次设置

~~~text
SWITCHGEAR
Switch profiles. Keep credentials isolated.

Account layout
  [1] Dual account — supported
  [2] Three account — coming later

Select [1]: 1

Secondary profile label [B]: B

Where should B be available?
  [1] CLI
  [2] VS Code
  [3] Both

Select [3]: 3

Workspace: D:\projects\my-project
Create desktop shortcut for VS Code? [Y/n]: Y

Review
  Mode       Dual account
  Profile    B
  Surfaces   CLI, VS Code
  Workspace  D:\projects\my-project
  Credentials are never copied or inspected.

Apply this setup? [y/N]: y

READY
  switchgear B cli
  switchgear B vscode
  switchgear doctor B
~~~

## Daily commands

~~~text
switchgear B
switchgear B cli
switchgear B vscode
switchgear list
switchgear doctor B
~~~

The command switchgear B opens the profile's chosen default surface.

## States

- **Success:** show READY and the exact next commands.
- **Warning:** show WARN with one corrective action, such as closing every VS Code window.
- **Failure:** show FAIL, explain what was not changed, and return a non-zero exit code.
- **Empty:** list explains that no profile exists and points to switchgear setup.
- **Unsupported:** choosing three accounts explains that the mode is planned and makes no changes.

## Visual rules

- Use a compact text header only for setup and help; daily commands stay quiet.
- Use labels in aligned columns and never rely on color alone.
- Never print email addresses, account identifiers, tokens, cookies, or credential-file contents.
- Show every filesystem target before the confirmation prompt.
- Verify the terminal presentation at 100%, 125%, and 150% Windows scaling with narrow and standard terminal widths.
