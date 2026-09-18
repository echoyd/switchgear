[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$ProfileName,

    [Parameter(Mandatory = $true)]
    [string]$CodexHome,

    [Parameter(Mandatory = $true)]
    [string]$Workspace,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [ValidateSet('CLI', 'VSCode')]
    [string[]]$Targets = @('CLI', 'VSCode'),

    [string]$CodexPath,

    [string]$VsCodePath,

    [switch]$ConfigureFileCredentialStore,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$MustExist,

        [switch]$MustBeDirectory
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $fullPath = [IO.Path]::GetFullPath($expanded)

    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "Path does not exist: $fullPath"
    }

    if ($MustBeDirectory -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Path is not a directory: $fullPath"
    }

    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Resolve-Executable {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName
    )

    if ($ExplicitPath) {
        $resolved = Resolve-FullPath -Path $ExplicitPath -MustExist
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
            throw "$DisplayName path is not a file: $resolved"
        }
        return $resolved
    }

    foreach ($commandName in $CommandNames) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }

    throw "$DisplayName was not found. Pass its explicit path."
}

function Assert-SafeCmdValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($Value -match '[%&|<>!\^"]' -or
        $Value.IndexOf([char]13) -ge 0 -or
        $Value.IndexOf([char]10) -ge 0) {
        throw "$Name contains characters that cannot be safely embedded in a Windows launcher."
    }
}

function Test-IsWithinPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,
        [Parameter(Mandatory = $true)]
        [string]$Parent
    )

    $separator = [IO.Path]::DirectorySeparatorChar
    $normalizedParent = $Parent.TrimEnd($separator, [IO.Path]::AltDirectorySeparatorChar) + $separator
    return $Candidate.StartsWith($normalizedParent, [StringComparison]::OrdinalIgnoreCase)
}

if (-not $Targets -or $Targets.Count -eq 0) {
    throw 'Select at least one target: CLI or VSCode.'
}

$selectedTargets = @($Targets | Select-Object -Unique)
$resolvedCodexHome = Resolve-FullPath -Path $CodexHome
$resolvedWorkspace = Resolve-FullPath -Path $Workspace -MustExist -MustBeDirectory
$resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory

if ($resolvedCodexHome.Equals($resolvedWorkspace, [StringComparison]::OrdinalIgnoreCase) -or
    (Test-IsWithinPath -Candidate $resolvedCodexHome -Parent $resolvedWorkspace) -or
    (Test-IsWithinPath -Candidate $resolvedWorkspace -Parent $resolvedCodexHome)) {
    throw 'CodexHome and the workspace must not contain one another.'
}

$resolvedCodexPath = $null
$resolvedVsCodePath = $null

if ($selectedTargets -contains 'CLI') {
    $resolvedCodexPath = Resolve-Executable -ExplicitPath $CodexPath -CommandNames @('codex.exe', 'codex.cmd', 'codex') -DisplayName 'Codex CLI'
}

if ($selectedTargets -contains 'VSCode') {
    $resolvedVsCodePath = Resolve-Executable -ExplicitPath $VsCodePath -CommandNames @('code.cmd', 'code.exe', 'code') -DisplayName 'Visual Studio Code'
}

foreach ($entry in @{
        CodexHome = $resolvedCodexHome
        Workspace = $resolvedWorkspace
        OutputDirectory = $resolvedOutputDirectory
        CodexPath = $resolvedCodexPath
        VsCodePath = $resolvedVsCodePath
    }.GetEnumerator()) {
    if ($null -ne $entry.Value) {
        Assert-SafeCmdValue -Value $entry.Value -Name $entry.Key
    }
}

$cliLauncherPath = $null
$vsCodeLauncherPath = $null

if ($selectedTargets -contains 'CLI') {
    $cliLauncherPath = Join-Path $resolvedOutputDirectory "Switchgear-$ProfileName-CLI.cmd"
}

if ($selectedTargets -contains 'VSCode') {
    $vsCodeLauncherPath = Join-Path $resolvedOutputDirectory "Switchgear-$ProfileName-VSCode.cmd"
}

$launcherPaths = @($cliLauncherPath, $vsCodeLauncherPath) | Where-Object { $_ }
foreach ($launcherPath in $launcherPaths) {
    if ((Test-Path -LiteralPath $launcherPath) -and -not $Force) {
        throw "Launcher already exists: $launcherPath. Re-run with -Force to replace generated launchers."
    }
}

$configPath = Join-Path $resolvedCodexHome 'config.toml'
$configDisposition = 'NotRequested'
if ($ConfigureFileCredentialStore) {
    if (Test-Path -LiteralPath $configPath) {
        $configDisposition = 'ExistingPreserved'
    }
    else {
        $configDisposition = 'Created'
    }
}

if ($PSCmdlet.ShouldProcess($resolvedCodexHome, 'Create isolated CODEX_HOME directory')) {
    [IO.Directory]::CreateDirectory($resolvedCodexHome) | Out-Null
}

if ($PSCmdlet.ShouldProcess($resolvedOutputDirectory, 'Create launcher output directory')) {
    [IO.Directory]::CreateDirectory($resolvedOutputDirectory) | Out-Null
}

$utf8NoBom = New-Object Text.UTF8Encoding($false)

if ($ConfigureFileCredentialStore -and $configDisposition -eq 'Created') {
    $configContent = @(
        '# Created by Switchgear. Authentication data is not stored in this file.'
        'cli_auth_credentials_store = "file"'
        ''
    )

    if ($PSCmdlet.ShouldProcess($configPath, 'Create minimal Codex credential-store configuration')) {
        [IO.File]::WriteAllLines($configPath, $configContent, $utf8NoBom)
    }
}

if ($cliLauncherPath) {
    $cliLauncher = @(
        '@echo off'
        'setlocal'
        ('set "CODEX_HOME={0}"' -f $resolvedCodexHome)
        ('set "CODEX_WORKSPACE={0}"' -f $resolvedWorkspace)
        ('set "CODEX_EXE={0}"' -f $resolvedCodexPath)
        'if not exist "%CODEX_HOME%" goto missing_profile'
        'if not exist "%CODEX_WORKSPACE%" goto missing_workspace'
        'if not exist "%CODEX_EXE%" goto missing_codex'
        'cd /d "%CODEX_WORKSPACE%" || goto workspace_error'
        'call "%CODEX_EXE%" %*'
        'set "SWITCHGEAR_EXIT=%ERRORLEVEL%"'
        'exit /b %SWITCHGEAR_EXIT%'
        ':missing_profile'
        'echo [Switchgear] CODEX_HOME does not exist: "%CODEX_HOME%"'
        'exit /b 11'
        ':missing_workspace'
        'echo [Switchgear] Workspace does not exist: "%CODEX_WORKSPACE%"'
        'exit /b 12'
        ':missing_codex'
        'echo [Switchgear] Codex CLI does not exist: "%CODEX_EXE%"'
        'exit /b 13'
        ':workspace_error'
        'echo [Switchgear] Could not enter workspace: "%CODEX_WORKSPACE%"'
        'exit /b 14'
    )

    if ($PSCmdlet.ShouldProcess($cliLauncherPath, 'Write isolated Codex CLI launcher')) {
        [IO.File]::WriteAllLines($cliLauncherPath, $cliLauncher, $utf8NoBom)
    }
}

if ($vsCodeLauncherPath) {
    $vsCodeLauncher = @(
        '@echo off'
        'setlocal'
        'tasklist /FI "IMAGENAME eq Code.exe" 2>NUL | find /I "Code.exe" >NUL'
        'if not errorlevel 1 goto vscode_running'
        ('set "CODEX_HOME={0}"' -f $resolvedCodexHome)
        ('set "CODEX_WORKSPACE={0}"' -f $resolvedWorkspace)
        ('set "VSCODE_EXE={0}"' -f $resolvedVsCodePath)
        'if not exist "%CODEX_HOME%" goto missing_profile'
        'if not exist "%CODEX_WORKSPACE%" goto missing_workspace'
        'if not exist "%VSCODE_EXE%" goto missing_vscode'
        'cd /d "%CODEX_WORKSPACE%" || goto workspace_error'
        'call "%VSCODE_EXE%" "%CODEX_WORKSPACE%"'
        'exit /b %ERRORLEVEL%'
        ':vscode_running'
        'echo [Switchgear] Close every Visual Studio Code window before switching profiles.'
        'exit /b 20'
        ':missing_profile'
        'echo [Switchgear] CODEX_HOME does not exist: "%CODEX_HOME%"'
        'exit /b 21'
        ':missing_workspace'
        'echo [Switchgear] Workspace does not exist: "%CODEX_WORKSPACE%"'
        'exit /b 22'
        ':missing_vscode'
        'echo [Switchgear] Visual Studio Code does not exist: "%VSCODE_EXE%"'
        'exit /b 23'
        ':workspace_error'
        'echo [Switchgear] Could not enter workspace: "%CODEX_WORKSPACE%"'
        'exit /b 24'
    )

    if ($PSCmdlet.ShouldProcess($vsCodeLauncherPath, 'Write isolated Codex VS Code launcher')) {
        [IO.File]::WriteAllLines($vsCodeLauncherPath, $vsCodeLauncher, $utf8NoBom)
    }
}

[pscustomobject]@{
    Product = 'Switchgear'
    ProfileName = $ProfileName
    CodexHome = $resolvedCodexHome
    Workspace = $resolvedWorkspace
    Targets = $selectedTargets
    Launchers = [pscustomobject]@{
        CLI = $cliLauncherPath
        VSCode = $vsCodeLauncherPath
    }
    Executables = [pscustomobject]@{
        CLI = $resolvedCodexPath
        VSCode = $resolvedVsCodePath
    }
    ConfigPath = $configPath
    ConfigDisposition = $configDisposition
    DryRun = [bool]$WhatIfPreference
}
