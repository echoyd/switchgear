[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param(
    [string]$InstallDirectory,

    [switch]$SkipPathCleanup,

    [switch]$RemoveProfileData,

    [switch]$CommandWrapper,

    [string]$BootstrapDirectory,

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

if ([string]::IsNullOrWhiteSpace($InstallDirectory)) {
    $InstallDirectory = Get-SwitchgearDefaultInstallDirectory
}

$resolvedInstallDirectory = Assert-SwitchgearSafeDirectory -Path $InstallDirectory -Purpose 'InstallDirectory'
if (-not (Test-Path -LiteralPath $resolvedInstallDirectory -PathType Container)) {
    throw "Switchgear is not installed at: $resolvedInstallDirectory"
}

$manifest = Read-SwitchgearInstallManifest -InstallDirectory $resolvedInstallDirectory
$profileDataDirectory = Assert-SwitchgearSafeDirectory -Path $manifest.profileDataDirectory -Purpose 'ProfileDataDirectory'
$pathManagedByInstaller = if ($manifest.PSObject.Properties.Name -contains 'pathManagedByInstaller') {
    [bool]$manifest.pathManagedByInstaller
}
else {
    $manifest.PSObject.Properties.Name -contains 'pathRegistered' -and [bool]$manifest.pathRegistered
}

$resolvedBootstrapDirectory = $null
if ($CommandWrapper) {
    if ([string]::IsNullOrWhiteSpace($BootstrapDirectory)) {
        throw 'BootstrapDirectory is required when CommandWrapper is used.'
    }
    $resolvedBootstrapDirectory = Assert-SwitchgearSafeDirectory -Path $BootstrapDirectory -Purpose 'BootstrapDirectory'
    $systemTemp = Resolve-SwitchgearInstallerPath -Path ([IO.Path]::GetTempPath())
    $requiredTempPrefix = $systemTemp + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedBootstrapDirectory.StartsWith($requiredTempPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "BootstrapDirectory must be inside the system temp directory: $resolvedBootstrapDirectory"
    }
    if (-not (Test-Path -LiteralPath $resolvedBootstrapDirectory -PathType Container)) {
        throw "BootstrapDirectory does not exist: $resolvedBootstrapDirectory"
    }
}

if ($RemoveProfileData -and (Test-Path -LiteralPath $profileDataDirectory)) {
    $statePath = Join-Path $profileDataDirectory 'state.json'
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) {
        throw "Refusing to remove Profile data without a Switchgear state marker: $statePath"
    }
    try {
        $state = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    }
    catch {
        throw "Refusing to remove Profile data because state.json is invalid: $statePath"
    }
    if ($state.product -ne 'Switchgear' -or $state.schemaVersion -ne 1) {
        throw "Refusing to remove Profile data because state.json is not a supported Switchgear state: $statePath"
    }
}

$plan = [pscustomobject]@{
    Product = 'Switchgear'
    Action = 'Uninstall'
    InstallDirectory = $resolvedInstallDirectory
    ProfileDataDirectory = $profileDataDirectory
    RemoveProfileData = [bool]$RemoveProfileData
    CleanUserPath = ($pathManagedByInstaller -and -not $SkipPathCleanup)
    Status = if ($WhatIfPreference) { 'Preview' } else { 'Planned' }
}

Write-Host ''
Write-Host 'SWITCHGEAR UNINSTALLER' -ForegroundColor Cyan
Write-Host "Program:      $resolvedInstallDirectory (remove)"
Write-Host "Profile data: $profileDataDirectory $(if ($RemoveProfileData) { '(remove)' } else { '(preserve)' })"
Write-Host "User PATH:    $(if ($pathManagedByInstaller -and -not $SkipPathCleanup) { 'remove installer-managed entry' } else { 'unchanged' })"
Write-Host ''

if (-not $PSCmdlet.ShouldProcess($resolvedInstallDirectory, 'Uninstall Switchgear')) {
    if ($PassThru) {
        return $plan
    }
    return
}

if ($pathManagedByInstaller -and -not $SkipPathCleanup) {
    Remove-SwitchgearUserPathEntry -Entry $resolvedInstallDirectory | Out-Null
}

if ($RemoveProfileData -and (Test-Path -LiteralPath $profileDataDirectory)) {
    if ($PSCmdlet.ShouldProcess($profileDataDirectory, 'Permanently remove Switchgear Profile data')) {
        Remove-Item -LiteralPath $profileDataDirectory -Recurse -Force
    }
}

if ($CommandWrapper) {
    $pendingMarkerName = '.switchgear-remove-pending'
    $pendingMarkerPath = Join-Path $resolvedInstallDirectory $pendingMarkerName
    $markerValue = [string]$manifest.installId
    [IO.File]::WriteAllText($pendingMarkerPath, $markerValue, (New-Object Text.UTF8Encoding($false)))

    $keepNames = @('uninstall-switchgear.cmd', $pendingMarkerName)
    foreach ($item in @(Get-ChildItem -LiteralPath $resolvedInstallDirectory -Force)) {
        if ($keepNames -notcontains $item.Name) {
            Remove-Item -LiteralPath $item.FullName -Recurse -Force
        }
    }

    $handoff = [ordered]@{
        schemaVersion = 1
        product = 'Switchgear'
        installDirectory = $resolvedInstallDirectory
        markerValue = $markerValue
    }
    $handoffPath = Join-Path $resolvedBootstrapDirectory 'cleanup.json'
    [IO.File]::WriteAllText(
        $handoffPath,
        (($handoff | ConvertTo-Json -Depth 3) + [Environment]::NewLine),
        (New-Object Text.UTF8Encoding($false))
    )
}
else {
    Remove-Item -LiteralPath $resolvedInstallDirectory -Recurse -Force
}

$profileDataPreserved = Test-Path -LiteralPath $profileDataDirectory
$result = [pscustomobject]@{
    Product = 'Switchgear'
    Action = 'Uninstall'
    InstallDirectory = $resolvedInstallDirectory
    ProfileDataDirectory = $profileDataDirectory
    ProfileDataPreserved = $profileDataPreserved
    Status = if ($CommandWrapper) { 'RemovalScheduled' } else { 'Removed' }
}

if ($CommandWrapper) {
    Write-Host 'SCHEDULED - Switchgear program files were removed; the command entry will be cleaned after exit.' -ForegroundColor Green
}
else {
    Write-Host 'REMOVED - Switchgear program files were removed.' -ForegroundColor Green
}
if ($profileDataPreserved) {
    Write-Host "PRESERVED - Profile data remains at: $profileDataDirectory"
}

if ($PassThru) {
    return $result
}
