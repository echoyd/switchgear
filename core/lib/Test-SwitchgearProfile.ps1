[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CodexHome,

    [string]$Workspace,

    [ValidateSet('CLI', 'VSCode')]
    [string[]]$Targets = @('CLI', 'VSCode'),

    [string]$CodexPath,

    [string]$VsCodePath,

    [switch]$SkipAuthCheck,

    [switch]$AsJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-FullPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Resolve-OptionalExecutable {
    param(
        [string]$ExplicitPath,
        [Parameter(Mandatory = $true)]
        [string[]]$CommandNames
    )

    if ($ExplicitPath) {
        $candidate = Resolve-FullPath -Path $ExplicitPath
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return $candidate
        }
        return $null
    }

    foreach ($commandName in $CommandNames) {
        $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }

    return $null
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

$checks = [Collections.Generic.List[object]]::new()

function Add-Check {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('PASS', 'WARN', 'FAIL')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $checks.Add([pscustomobject]@{
            Name = $Name
            Status = $Status
            Message = $Message
        })
}

if (-not $Targets -or $Targets.Count -eq 0) {
    throw 'Select at least one target: CLI or VSCode.'
}

$selectedTargets = @($Targets | Select-Object -Unique)
$resolvedCodexHome = Resolve-FullPath -Path $CodexHome
$resolvedWorkspace = $null
$resolvedCodexPath = $null
$resolvedVsCodePath = $null

if (Test-Path -LiteralPath $resolvedCodexHome -PathType Container) {
    Add-Check -Name 'CODEX_HOME directory' -Status 'PASS' -Message 'The isolated profile directory exists.'
}
else {
    Add-Check -Name 'CODEX_HOME directory' -Status 'FAIL' -Message 'The isolated profile directory does not exist.'
}

if ($Workspace) {
    $resolvedWorkspace = Resolve-FullPath -Path $Workspace
    if (-not (Test-Path -LiteralPath $resolvedWorkspace -PathType Container)) {
        Add-Check -Name 'Workspace directory' -Status 'FAIL' -Message 'The workspace directory does not exist.'
    }
    elseif ($resolvedCodexHome.Equals($resolvedWorkspace, [StringComparison]::OrdinalIgnoreCase) -or
        (Test-IsWithinPath -Candidate $resolvedCodexHome -Parent $resolvedWorkspace) -or
        (Test-IsWithinPath -Candidate $resolvedWorkspace -Parent $resolvedCodexHome)) {
        Add-Check -Name 'Profile and workspace isolation' -Status 'FAIL' -Message 'CODEX_HOME and the workspace must not contain one another.'
    }
    else {
        Add-Check -Name 'Profile and workspace isolation' -Status 'PASS' -Message 'CODEX_HOME and the workspace are separate directory trees.'
    }

    $workspaceSettingsPath = Join-Path $resolvedWorkspace '.vscode\settings.json'
    if (Test-Path -LiteralPath $workspaceSettingsPath -PathType Leaf) {
        $workspaceSettings = [IO.File]::ReadAllText($workspaceSettingsPath)
        if ($workspaceSettings -match 'CODEX_HOME') {
            Add-Check -Name 'Workspace VS Code settings' -Status 'FAIL' -Message 'The shared workspace settings mention CODEX_HOME. Profile selection must stay in launcher process state.'
        }
        else {
            Add-Check -Name 'Workspace VS Code settings' -Status 'PASS' -Message 'The shared workspace settings do not select a Codex profile.'
        }
    }
    else {
        Add-Check -Name 'Workspace VS Code settings' -Status 'PASS' -Message 'No shared VS Code settings file selects a Codex profile.'
    }
}

$configPath = Join-Path $resolvedCodexHome 'config.toml'
if (Test-Path -LiteralPath $configPath -PathType Leaf) {
    Add-Check -Name 'Profile configuration' -Status 'PASS' -Message 'A profile-local config.toml exists; its contents were not read.'
}
else {
    Add-Check -Name 'Profile configuration' -Status 'WARN' -Message 'No profile-local config.toml exists. Codex defaults may still be valid.'
}

if ($selectedTargets -contains 'CLI') {
    $resolvedCodexPath = Resolve-OptionalExecutable -ExplicitPath $CodexPath -CommandNames @('codex.exe', 'codex.cmd', 'codex')
    if ($resolvedCodexPath) {
        Add-Check -Name 'Codex CLI' -Status 'PASS' -Message 'The Codex CLI executable is available.'
    }
    else {
        Add-Check -Name 'Codex CLI' -Status 'FAIL' -Message 'The Codex CLI executable was not found.'
    }
}

if ($selectedTargets -contains 'VSCode') {
    $resolvedVsCodePath = Resolve-OptionalExecutable -ExplicitPath $VsCodePath -CommandNames @('code.cmd', 'code.exe', 'code')
    if ($resolvedVsCodePath) {
        Add-Check -Name 'Visual Studio Code' -Status 'PASS' -Message 'The Visual Studio Code launcher is available.'
    }
    else {
        Add-Check -Name 'Visual Studio Code' -Status 'FAIL' -Message 'The Visual Studio Code launcher was not found.'
    }

    $codeProcess = Get-Process -Name 'Code' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($codeProcess) {
        Add-Check -Name 'VS Code profile switch safety' -Status 'WARN' -Message 'VS Code is running. Close every window before switching profiles.'
    }
    else {
        Add-Check -Name 'VS Code profile switch safety' -Status 'PASS' -Message 'No running VS Code process was detected.'
    }
}

if (-not $SkipAuthCheck) {
    if (-not $resolvedCodexPath) {
        $resolvedCodexPath = Resolve-OptionalExecutable -ExplicitPath $CodexPath -CommandNames @('codex.exe', 'codex.cmd', 'codex')
    }

    if (-not (Test-Path -LiteralPath $resolvedCodexHome -PathType Container)) {
        Add-Check -Name 'Codex authentication' -Status 'FAIL' -Message 'Authentication status cannot be checked until CODEX_HOME exists.'
    }
    elseif (-not $resolvedCodexPath) {
        Add-Check -Name 'Codex authentication' -Status 'WARN' -Message 'Authentication status was not checked because Codex CLI was unavailable.'
    }
    else {
        $previousCodexHome = $env:CODEX_HOME
        try {
            $env:CODEX_HOME = $resolvedCodexHome
            $null = & $resolvedCodexPath login status 2>&1
            $authExitCode = $LASTEXITCODE
        }
        finally {
            if ($null -eq $previousCodexHome) {
                Remove-Item Env:CODEX_HOME -ErrorAction SilentlyContinue
            }
            else {
                $env:CODEX_HOME = $previousCodexHome
            }
        }

        if ($authExitCode -eq 0) {
            Add-Check -Name 'Codex authentication' -Status 'PASS' -Message 'Codex reports that this isolated profile is authenticated.'
        }
        else {
            Add-Check -Name 'Codex authentication' -Status 'WARN' -Message 'Codex reports that this isolated profile is not authenticated or needs attention.'
        }
    }
}
else {
    Add-Check -Name 'Codex authentication' -Status 'WARN' -Message 'Authentication check was skipped by request.'
}

$failed = @($checks | Where-Object Status -eq 'FAIL').Count
$warnings = @($checks | Where-Object Status -eq 'WARN').Count
$report = [pscustomobject]@{
    SchemaVersion = 2
    Product = 'Switchgear'
    CodexHome = $resolvedCodexHome
    Workspace = $resolvedWorkspace
    Targets = $selectedTargets
    Healthy = ($failed -eq 0)
    FailedChecks = $failed
    Warnings = $warnings
    Checks = $checks
}

if ($AsJson) {
    $report | ConvertTo-Json -Depth 5
}
else {
    Write-Host 'Switchgear profile health'
    Write-Host "CODEX_HOME: $resolvedCodexHome"
    Write-Host "Targets: $($selectedTargets -join ', ')"
    $checks | Format-Table -AutoSize
    Write-Host "Healthy: $($report.Healthy) | Warnings: $warnings | Failed: $failed"
}

if ($failed -gt 0) {
    exit 1
}
