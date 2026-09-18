[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
$version = [IO.File]::ReadAllText((Join-Path $sourceRoot 'VERSION')).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') {
    throw "A release requires a stable semantic VERSION; found '$version'."
}

$releaseDirectory = Join-Path $outputRoot ("{0}-v{1}" -f (Get-Date -Format 'yyyy-MM'), $version)
if (Test-Path -LiteralPath $releaseDirectory) {
    throw "Release staging directory already exists; refusing to overwrite: $releaseDirectory"
}

$assetBaseName = "Switchgear-$version-windows-x64"
$payloadDirectory = Join-Path $releaseDirectory $assetBaseName
$archivePath = Join-Path $releaseDirectory "$assetBaseName.zip"
$checksumsPath = Join-Path $releaseDirectory 'SHA256SUMS.txt'
$releaseNotesPath = Join-Path $releaseDirectory 'RELEASE_NOTES.md'
$items = @(
    'START-HERE.cmd',
    'switchgear.cmd',
    'install-switchgear.cmd',
    'uninstall-switchgear.cmd',
    'VERSION',
    'README.md',
    'LICENSE',
    'SECURITY.md',
    'core',
    'installer',
    'skill'
)

foreach ($item in $items) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot $item))) {
        throw "Release source item is missing: $item"
    }
}
if (-not (Test-Path -LiteralPath (Join-Path $sourceRoot 'RELEASE_NOTES.md') -PathType Leaf)) {
    throw 'RELEASE_NOTES.md is missing.'
}

[IO.Directory]::CreateDirectory($payloadDirectory) | Out-Null
foreach ($item in $items) {
    Copy-Item -LiteralPath (Join-Path $sourceRoot $item) -Destination $payloadDirectory -Recurse
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'RELEASE_NOTES.md') -Destination $releaseNotesPath

Compress-Archive -Path (Join-Path $payloadDirectory '*') -DestinationPath $archivePath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
$checksumLine = "$hash  $assetBaseName.zip`r`n"
[IO.File]::WriteAllText($checksumsPath, $checksumLine, (New-Object Text.UTF8Encoding($false)))

[pscustomobject]@{
    Version = $version
    ReleaseDirectory = $releaseDirectory
    ArchivePath = $archivePath
    ChecksumsPath = $checksumsPath
    Sha256 = $hash
}
