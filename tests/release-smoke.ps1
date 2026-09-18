Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$testRoot = Join-Path $systemTemp ("switchgear-release-test-{0}" -f [Guid]::NewGuid().ToString('N'))
$resolvedTestRoot = [IO.Path]::GetFullPath($testRoot)
if (-not $resolvedTestRoot.StartsWith(($systemTemp + '\'), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Release test root must be inside system temp.'
}

try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null
    $buildResult = & (Join-Path $projectRoot 'scripts\Build-Release.ps1') -OutputDirectory (Join-Path $testRoot 'staging')
    if (-not (Test-Path -LiteralPath $buildResult.ArchivePath -PathType Leaf)) {
        throw 'Release ZIP was not created.'
    }
    $actualHash = (Get-FileHash -LiteralPath $buildResult.ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $checksum = [IO.File]::ReadAllText($buildResult.ChecksumsPath).Trim()
    if ($checksum -ne "$actualHash  Switchgear-$($buildResult.Version)-windows-x64.zip") {
        throw 'Release checksum does not match the ZIP.'
    }

    $extractDirectory = Join-Path $testRoot 'extracted'
    Expand-Archive -LiteralPath $buildResult.ArchivePath -DestinationPath $extractDirectory
    foreach ($required in @('START-HERE.cmd', 'switchgear.cmd', 'install-switchgear.cmd', 'uninstall-switchgear.cmd', 'README.md', 'LICENSE', 'SECURITY.md', 'core\Switchgear.ps1', 'skill\profile-switchgear\SKILL.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $extractDirectory $required) -PathType Leaf)) {
            throw "Extracted package is missing: $required"
        }
    }
    foreach ($forbidden in @('AGENTS.md', '项目转接说明.md', '开发日志.md', '验收记录.md', 'auth.json', 'state.json')) {
        if (@(Get-ChildItem -LiteralPath $extractDirectory -Recurse -Force -File | Where-Object { $_.Name -eq $forbidden }).Count -gt 0) {
            throw "Forbidden file entered release ZIP: $forbidden"
        }
    }

    & (Join-Path $extractDirectory 'switchgear.cmd') help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Extracted switchgear.cmd help failed.' }

    $programDirectory = Join-Path $testRoot 'programs\Switchgear'
    $dataDirectory = Join-Path $testRoot 'data\Switchgear'
    & (Join-Path $extractDirectory 'install-switchgear.cmd') -InstallDirectory $programDirectory -ProfileDataDirectory $dataDirectory -SkipPathRegistration -Yes | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath (Join-Path $programDirectory 'switchgear.cmd') -PathType Leaf)) {
        throw 'Installing the extracted package into temp failed.'
    }
    & (Join-Path $programDirectory 'switchgear.cmd') help | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Installed switchgear.cmd help failed.' }

    Write-Output 'PASS: release ZIP, checksum, public file boundary, extraction, and temp-only install passed.'
}
finally {
    if ((Test-Path -LiteralPath $resolvedTestRoot) -and $resolvedTestRoot.StartsWith(($systemTemp + '\switchgear-release-test-'), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
