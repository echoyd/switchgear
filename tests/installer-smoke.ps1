[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$installScript = Join-Path $projectRoot 'installer\Install-Switchgear.ps1'
$uninstallScript = Join-Path $projectRoot 'installer\Uninstall-Switchgear.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempRoot ("switchgear-installer-{0}" -f [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $threw = $false
    try {
        & $Action
    }
    catch {
        $threw = $true
    }
    if (-not $threw) {
        throw $Message
    }
}

try {
    $installDirectory = Join-Path $testRoot 'programs\Switchgear'
    $profileDataDirectory = Join-Path $testRoot 'data\Switchgear'
    $pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

    $preview = & $installScript `
        -SourceRoot $projectRoot `
        -InstallDirectory $installDirectory `
        -ProfileDataDirectory $profileDataDirectory `
        -SkipPathRegistration `
        -WhatIf `
        -PassThru
    Assert-True -Condition ($preview.Status -eq 'Preview') -Message 'Installer WhatIf did not return Preview.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $installDirectory)) -Message 'Installer WhatIf created the program directory.'

    [IO.Directory]::CreateDirectory($profileDataDirectory) | Out-Null
    $statePath = Join-Path $profileDataDirectory 'state.json'
    $stateText = '{"schemaVersion":1,"product":"Switchgear","profiles":[]}' + [Environment]::NewLine
    [IO.File]::WriteAllText($statePath, $stateText, (New-Object Text.UTF8Encoding($false)))
    $profileSentinel = Join-Path $profileDataDirectory 'preserve-me.txt'
    [IO.File]::WriteAllText($profileSentinel, 'profile data must survive updates and default uninstall')

    $installed = & $installScript `
        -SourceRoot $projectRoot `
        -InstallDirectory $installDirectory `
        -ProfileDataDirectory $profileDataDirectory `
        -SkipPathRegistration `
        -Confirm:$false `
        -PassThru
    Assert-True -Condition ($installed.Status -eq 'Ready') -Message 'Installer did not return Ready.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installDirectory 'switchgear.cmd') -PathType Leaf) -Message 'Installed switchgear.cmd is missing.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installDirectory 'core\Switchgear.ps1') -PathType Leaf) -Message 'Installed core is missing.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installDirectory '.switchgear-install.json') -PathType Leaf) -Message 'Install marker is missing.'

    $helpOutput = & (Join-Path $installDirectory 'switchgear.cmd') help 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Installed command failed: $($helpOutput -join ' ')"
    Assert-True -Condition (($helpOutput -join [Environment]::NewLine).Contains('SWITCHGEAR')) -Message 'Installed command did not display Switchgear help.'

    Assert-Throws -Message 'Installer overwrote a managed install without -Update.' -Action {
        & $installScript `
            -SourceRoot $projectRoot `
            -InstallDirectory $installDirectory `
            -ProfileDataDirectory $profileDataDirectory `
            -SkipPathRegistration `
            -Confirm:$false | Out-Null
    }

    $installedReadme = Join-Path $installDirectory 'README.md'
    [IO.File]::WriteAllText($installedReadme, 'stale installed copy')
    $updated = & $installScript `
        -SourceRoot $projectRoot `
        -InstallDirectory $installDirectory `
        -ProfileDataDirectory $profileDataDirectory `
        -Update `
        -SkipPathRegistration `
        -Confirm:$false `
        -PassThru
    Assert-True -Condition ($updated.Action -eq 'Update' -and $updated.Status -eq 'Ready') -Message 'Update did not complete.'
    Assert-True -Condition ([IO.File]::ReadAllText($installedReadme).Contains('# Switchgear')) -Message 'Update did not replace program files.'
    Assert-True -Condition (Test-Path -LiteralPath $profileSentinel -PathType Leaf) -Message 'Update removed Profile data.'

    Assert-Throws -Message 'Update accepted a different Profile data directory.' -Action {
        & $installScript `
            -SourceRoot $projectRoot `
            -InstallDirectory $installDirectory `
            -ProfileDataDirectory (Join-Path $testRoot 'different-data\Switchgear') `
            -Update `
            -SkipPathRegistration `
            -Confirm:$false | Out-Null
    }

    $installedUninstallScript = Join-Path $installDirectory 'installer\Uninstall-Switchgear.ps1'
    $uninstallPreview = & $installedUninstallScript `
        -InstallDirectory $installDirectory `
        -SkipPathCleanup `
        -WhatIf `
        -PassThru
    Assert-True -Condition ($uninstallPreview.Status -eq 'Preview') -Message 'Uninstaller WhatIf did not return Preview.'
    Assert-True -Condition (Test-Path -LiteralPath $installDirectory -PathType Container) -Message 'Uninstaller WhatIf removed the program directory.'

    $removed = & $installedUninstallScript `
        -InstallDirectory $installDirectory `
        -SkipPathCleanup `
        -Confirm:$false `
        -PassThru
    Assert-True -Condition ($removed.Status -eq 'Removed') -Message 'Uninstaller did not return Removed.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $installDirectory)) -Message 'Uninstaller left the program directory behind.'
    Assert-True -Condition (Test-Path -LiteralPath $profileSentinel -PathType Leaf) -Message 'Default uninstall removed Profile data.'

    $unmanagedDirectory = Join-Path $testRoot 'unmanaged\Switchgear'
    [IO.Directory]::CreateDirectory($unmanagedDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $unmanagedDirectory 'user-file.txt'), 'do not delete')
    Assert-Throws -Message 'Uninstaller accepted an unmanaged directory.' -Action {
        & $uninstallScript -InstallDirectory $unmanagedDirectory -SkipPathCleanup -Confirm:$false | Out-Null
    }
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $unmanagedDirectory 'user-file.txt') -PathType Leaf) -Message 'Uninstaller damaged an unmanaged directory.'

    $pathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-True -Condition ([string]::Equals([string]$pathBefore, [string]$pathAfter, [StringComparison]::Ordinal)) -Message 'Installer tests changed the real user PATH.'

    $installerSource = [IO.File]::ReadAllText($installScript)
    $uninstallerSource = [IO.File]::ReadAllText($uninstallScript)
    Assert-True -Condition (-not $installerSource.Contains('auth.json')) -Message 'Installer contains credential-file handling.'
    Assert-True -Condition (-not $uninstallerSource.Contains('auth.json')) -Message 'Uninstaller contains credential-file handling.'

    Write-Output 'PASS: temp-only install, update, installed uninstaller, managed-directory boundaries, PATH isolation, and Profile-data preservation passed.'
}
finally {
    $resolvedTestRoot = [IO.Path]::GetFullPath($testRoot).TrimEnd('\', '/')
    $requiredPrefix = $tempRoot + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTestRoot.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to remove a test path outside the system temp directory: $resolvedTestRoot"
    }
    if (Test-Path -LiteralPath $resolvedTestRoot) {
        Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
    }
}
