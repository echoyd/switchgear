[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$SourceRoot,

    [string]$InstallDirectory,

    [string]$ProfileDataDirectory,

    [switch]$Update,

    [switch]$SkipPathRegistration,

    [switch]$Yes,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Yes) {
    $ConfirmPreference = 'None'
}

$helperPath = Join-Path $PSScriptRoot 'lib\InstallHelpers.ps1'
if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) {
    throw "Installer helper is missing: $helperPath"
}
. $helperPath

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Split-Path -Parent $PSScriptRoot
}
if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Get-SwitchgearDefaultInstallDirectory
}
if ([string]::IsNullOrWhiteSpace($ProfileDataDirectory)) {
    $ProfileDataDirectory = Get-SwitchgearDefaultProfileDataDirectory
}

$resolvedSourceRoot = Resolve-SwitchgearInstallerPath -Path $SourceRoot
$resolvedInstallDirectory = Assert-SwitchgearSafeDirectory -Path $InstallDirectory -Purpose 'InstallDirectory'
$resolvedProfileDataDirectory = Assert-SwitchgearSafeDirectory -Path $ProfileDataDirectory -Purpose 'ProfileDataDirectory'

if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
    throw "SourceRoot does not exist: $resolvedSourceRoot"
}
if (Test-SwitchgearPathEquals -Left $resolvedSourceRoot -Right $resolvedInstallDirectory) {
    throw 'SourceRoot and InstallDirectory must be different directories.'
}

$requiredSourceItems = @(
    'core',
    'installer',
    'switchgear.cmd',
    'uninstall-switchgear.cmd',
    'README.md',
    'VERSION'
)
foreach ($relativePath in $requiredSourceItems) {
    $sourcePath = Join-Path $resolvedSourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required installer source item is missing: $sourcePath"
    }
}

$version = [IO.File]::ReadAllText((Join-Path $resolvedSourceRoot 'VERSION')).Trim()
if ([string]::IsNullOrWhiteSpace($version)) {
    throw 'VERSION is empty.'
}

$existingManifest = $null
$installExists = Test-Path -LiteralPath $resolvedInstallDirectory -PathType Container
if ($installExists) {
    $items = @(Get-ChildItem -LiteralPath $resolvedInstallDirectory -Force)
    if ($items.Count -gt 0) {
        if (-not $Update) {
            throw "InstallDirectory is not empty. Use -Update only for an existing managed Switchgear installation: $resolvedInstallDirectory"
        }
        $existingManifest = Read-SwitchgearInstallManifest -InstallDirectory $resolvedInstallDirectory
    }
    elseif ($Update) {
        throw 'Update was requested, but InstallDirectory is empty.'
    }
}
elseif ($Update) {
    throw "Update was requested, but Switchgear is not installed at: $resolvedInstallDirectory"
}

if ($existingManifest) {
    $existingProfileDataDirectory = Assert-SwitchgearSafeDirectory -Path $existingManifest.profileDataDirectory -Purpose 'Existing ProfileDataDirectory'
    if ($PSBoundParameters.ContainsKey('ProfileDataDirectory')) {
        if (-not (Test-SwitchgearPathEquals -Left $resolvedProfileDataDirectory -Right $existingProfileDataDirectory)) {
            throw 'ProfileDataDirectory cannot be changed during an update. Uninstalling also preserves the existing Profile data directory.'
        }
    }
    else {
        $resolvedProfileDataDirectory = $existingProfileDataDirectory
    }
}

$action = if ($existingManifest) { 'Update' } else { 'Install' }
$pathWasManaged = if ($existingManifest -and $existingManifest.PSObject.Properties.Name -contains 'pathManagedByInstaller') {
    [bool]$existingManifest.pathManagedByInstaller
}
elseif ($existingManifest -and $existingManifest.PSObject.Properties.Name -contains 'pathRegistered') {
    [bool]$existingManifest.pathRegistered
}
else {
    $false
}
$userPathBeforeInstall = Get-SwitchgearUserPath
$pathWasAvailable = Test-SwitchgearPathContains -Value $userPathBeforeInstall -Entry $resolvedInstallDirectory
$plannedPathAvailable = $pathWasAvailable -or (-not $SkipPathRegistration)
$plannedPathManaged = $pathWasManaged -or ((-not $SkipPathRegistration) -and (-not $pathWasAvailable))
$installId = if ($existingManifest -and $existingManifest.PSObject.Properties.Name -contains 'installId') {
    [string]$existingManifest.installId
}
else {
    [Guid]::NewGuid().ToString('D')
}

$plan = [pscustomobject]@{
    Product = 'Switchgear'
    Action = $action
    Version = $version
    InstallDirectory = $resolvedInstallDirectory
    ProfileDataDirectory = $resolvedProfileDataDirectory
    RegisterUserPath = (-not $SkipPathRegistration)
    ProfileDataPolicy = 'Preserve'
    Status = if ($WhatIfPreference) { 'Preview' } else { 'Planned' }
}

Write-Host ''
Write-Host 'SWITCHGEAR INSTALLER' -ForegroundColor Cyan
Write-Host "Action:       $action"
Write-Host "Version:      $version"
Write-Host "Program:      $resolvedInstallDirectory"
Write-Host "Profile data: $resolvedProfileDataDirectory (preserved)"
Write-Host "User PATH:    $(if ($SkipPathRegistration) { 'unchanged' } else { 'register program directory' })"
Write-Host ''

if (-not $PSCmdlet.ShouldProcess($resolvedInstallDirectory, "$action Switchgear $version")) {
    if ($PassThru) {
        return $plan
    }
    return
}

$parentDirectory = Split-Path -Parent $resolvedInstallDirectory
[IO.Directory]::CreateDirectory($parentDirectory) | Out-Null
$leafName = Split-Path -Leaf $resolvedInstallDirectory
$stageDirectory = Join-Path $parentDirectory (".{0}-stage-{1}" -f $leafName, [Guid]::NewGuid().ToString('N'))
$backupDirectory = Join-Path $parentDirectory (".{0}-backup-{1}" -f $leafName, [Guid]::NewGuid().ToString('N'))
$movedExistingInstall = $false
$installedNewDirectory = $false
$pathAddedThisRun = $false
$utf8NoBom = New-Object Text.UTF8Encoding($false)

try {
    [IO.Directory]::CreateDirectory($stageDirectory) | Out-Null
    foreach ($relativePath in $requiredSourceItems) {
        Copy-Item -LiteralPath (Join-Path $resolvedSourceRoot $relativePath) -Destination $stageDirectory -Recurse -Force
    }

    $manifest = [ordered]@{
        schemaVersion = 1
        product = 'Switchgear'
        version = $version
        installId = $installId
        installDirectory = $resolvedInstallDirectory
        profileDataDirectory = $resolvedProfileDataDirectory
        pathRegistered = $plannedPathAvailable
        pathManagedByInstaller = $plannedPathManaged
        installedAt = [DateTimeOffset]::Now.ToString('o')
    }
    $manifestJson = $manifest | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText(
        (Join-Path $stageDirectory '.switchgear-install.json'),
        ($manifestJson + [Environment]::NewLine),
        $utf8NoBom
    )

    if (Test-Path -LiteralPath $resolvedInstallDirectory) {
        $remainingItems = @(Get-ChildItem -LiteralPath $resolvedInstallDirectory -Force)
        if ($remainingItems.Count -eq 0) {
            Remove-Item -LiteralPath $resolvedInstallDirectory -Force
        }
        else {
            Move-Item -LiteralPath $resolvedInstallDirectory -Destination $backupDirectory
            $movedExistingInstall = $true
        }
    }

    Move-Item -LiteralPath $stageDirectory -Destination $resolvedInstallDirectory
    $installedNewDirectory = $true

    if (-not $SkipPathRegistration) {
        $pathAddedThisRun = Add-SwitchgearUserPathEntry -Entry $resolvedInstallDirectory
    }

    if ($movedExistingInstall -and (Test-Path -LiteralPath $backupDirectory)) {
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force
        $movedExistingInstall = $false
    }
}
catch {
    if ($pathAddedThisRun) {
        Remove-SwitchgearUserPathEntry -Entry $resolvedInstallDirectory | Out-Null
    }
    if ($installedNewDirectory -and (Test-Path -LiteralPath $resolvedInstallDirectory)) {
        Remove-Item -LiteralPath $resolvedInstallDirectory -Recurse -Force
    }
    if ($movedExistingInstall -and (Test-Path -LiteralPath $backupDirectory)) {
        Move-Item -LiteralPath $backupDirectory -Destination $resolvedInstallDirectory
        $movedExistingInstall = $false
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $stageDirectory) {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force
    }
    if ($movedExistingInstall -and (Test-Path -LiteralPath $backupDirectory)) {
        throw "Installer rollback backup still exists: $backupDirectory"
    }
}

$result = [pscustomobject]@{
    Product = 'Switchgear'
    Action = $action
    Version = $version
    InstallDirectory = $resolvedInstallDirectory
    ProfileDataDirectory = $resolvedProfileDataDirectory
    PathRegistered = $plannedPathAvailable
    PathManagedByInstaller = $plannedPathManaged
    PathChangedThisRun = $pathAddedThisRun
    Status = 'Ready'
}

Write-Host "READY - Switchgear $version is installed." -ForegroundColor Green
if (-not $SkipPathRegistration) {
    Write-Host 'Open a new terminal before using the global switchgear command.'
}
Write-Host 'Profile data was not read or changed.'

if ($PassThru) {
    return $result
}
