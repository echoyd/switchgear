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
$requiredTempPrefix = $systemTemp + [IO.Path]::DirectorySeparatorChar
if (-not $resolvedBootstrapDirectory.StartsWith($requiredTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    exit 2
}

$handoffPath = Join-Path $resolvedBootstrapDirectory 'cleanup.json'
if (-not (Test-Path -LiteralPath $handoffPath -PathType Leaf)) {
    exit 3
}

try {
    $handoff = [IO.File]::ReadAllText($handoffPath) | ConvertFrom-Json
    if ($handoff.product -ne 'Switchgear' -or $handoff.schemaVersion -ne 1) {
        exit 4
    }

    $installDirectory = [IO.Path]::GetFullPath(
        [Environment]::ExpandEnvironmentVariables([string]$handoff.installDirectory)
    ).TrimEnd('\', '/')
    $root = [IO.Path]::GetPathRoot($installDirectory).TrimEnd('\', '/')
    $relative = $installDirectory.Substring([IO.Path]::GetPathRoot($installDirectory).Length).Trim('\', '/')
    $segments = @($relative -split '[\\/]' | Where-Object { $_ })
    if ($installDirectory.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $segments.Count -lt 2) {
        exit 5
    }

    $pendingMarkerPath = Join-Path $installDirectory '.switchgear-remove-pending'
    if (-not (Test-Path -LiteralPath $pendingMarkerPath -PathType Leaf)) {
        exit 6
    }
    $actualMarker = [IO.File]::ReadAllText($pendingMarkerPath)
    if (-not $actualMarker.Equals([string]$handoff.markerValue, [StringComparison]::Ordinal)) {
        exit 7
    }

    Start-Sleep -Milliseconds 300
    $deadline = [DateTime]::UtcNow.AddSeconds(15)
    while ((Test-Path -LiteralPath $installDirectory) -and [DateTime]::UtcNow -lt $deadline) {
        try {
            Remove-Item -LiteralPath $installDirectory -Recurse -Force -ErrorAction Stop
        }
        catch {
            Start-Sleep -Milliseconds 100
        }
    }
    if (Test-Path -LiteralPath $installDirectory) {
        exit 8
    }
}
finally {
    if (Test-Path -LiteralPath $resolvedBootstrapDirectory) {
        Remove-Item -LiteralPath $resolvedBootstrapDirectory -Recurse -Force
    }
}
