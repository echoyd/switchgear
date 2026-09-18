[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BootstrapDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedBootstrapDirectory = [IO.Path]::GetFullPath(
    [Environment]::ExpandEnvironmentVariables($BootstrapDirectory)
).TrimEnd('\', '/')
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$requiredPrefix = $systemTemp + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedBootstrapDirectory.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to schedule cleanup outside the system temp directory: $resolvedBootstrapDirectory"
}

$handoffPath = Join-Path $resolvedBootstrapDirectory 'cleanup.json'
$completeScript = Join-Path $resolvedBootstrapDirectory 'installer\Complete-UninstallCleanup.ps1'
if (-not (Test-Path -LiteralPath $handoffPath -PathType Leaf)) {
    throw "Uninstall cleanup handoff is missing: $handoffPath"
}
if (-not (Test-Path -LiteralPath $completeScript -PathType Leaf)) {
    throw "Uninstall cleanup worker is missing: $completeScript"
}

$arguments = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    ('"{0}"' -f $completeScript),
    '-BootstrapDirectory',
    ('"{0}"' -f $resolvedBootstrapDirectory)
)

Start-Process `
    -FilePath 'powershell.exe' `
    -ArgumentList $arguments `
    -WindowStyle Hidden | Out-Null

Write-Output 'Cleanup scheduled.'
