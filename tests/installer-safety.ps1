[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$installWrapper = Join-Path $projectRoot 'install-switchgear.cmd'
$installScript = Join-Path $projectRoot 'installer\Install-Switchgear.ps1'
$uninstallScript = Join-Path $projectRoot 'installer\Uninstall-Switchgear.ps1'
$helperScript = Join-Path $projectRoot 'installer\lib\InstallHelpers.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempRoot ("switchgear-safety-{0}" -f [Guid]::NewGuid().ToString('N'))

. $helperScript

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
    $pathBefore = [Environment]::GetEnvironmentVariable('Path', 'User')

    $syntheticEntry = Join-Path $testRoot 'Programs\Switchgear'
    $syntheticPath = "C:\Windows\System32;$($syntheticEntry.ToUpperInvariant())\;C:\Tools"
    Assert-True -Condition (Test-SwitchgearPathContains -Value $syntheticPath -Entry $syntheticEntry) -Message 'PATH matching did not normalize case and trailing separators.'
    Assert-True -Condition (-not (Test-SwitchgearPathContains -Value $syntheticPath -Entry (Join-Path $testRoot 'Programs\Switchgear-Other'))) -Message 'PATH matching accepted a sibling directory.'

    $wrapperInstallDirectory = Join-Path $testRoot 'wrapper\Programs\Switchgear'
    $wrapperProfileDataDirectory = Join-Path $testRoot 'wrapper\Data\Switchgear'
    $wrapperInstallOutput = & $installWrapper `
        -SourceRoot $projectRoot `
        -InstallDirectory $wrapperInstallDirectory `
        -ProfileDataDirectory $wrapperProfileDataDirectory `
        -SkipPathRegistration `
        -Yes 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "CMD installer entry failed: $($wrapperInstallOutput -join ' ')"
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $wrapperInstallDirectory 'switchgear.cmd') -PathType Leaf) -Message 'CMD installer entry did not install the product.'

    [IO.Directory]::CreateDirectory($wrapperProfileDataDirectory) | Out-Null
    $wrapperStatePath = Join-Path $wrapperProfileDataDirectory 'state.json'
    [IO.File]::WriteAllText(
        $wrapperStatePath,
        ('{"schemaVersion":1,"product":"Switchgear","profiles":[]}' + [Environment]::NewLine),
        (New-Object Text.UTF8Encoding($false))
    )
    $wrapperDataSentinel = Join-Path $wrapperProfileDataDirectory 'temporary-profile-data.txt'
    [IO.File]::WriteAllText($wrapperDataSentinel, 'temporary test data')

    $installedUninstallWrapper = Join-Path $wrapperInstallDirectory 'uninstall-switchgear.cmd'
    $wrapperUninstallOutput = & $installedUninstallWrapper `
        -InstallDirectory $wrapperInstallDirectory `
        -SkipPathCleanup `
        -RemoveProfileData `
        -Yes 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Installed CMD uninstaller entry failed: $($wrapperUninstallOutput -join ' ')"
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(10)
    while ((Test-Path -LiteralPath $wrapperInstallDirectory) -and [DateTime]::UtcNow -lt $cleanupDeadline) {
        Start-Sleep -Milliseconds 100
    }
    Assert-True -Condition (-not (Test-Path -LiteralPath $wrapperInstallDirectory)) -Message 'Installed CMD uninstaller left program files behind.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $wrapperProfileDataDirectory)) -Message 'Explicit temporary Profile-data removal did not complete.'

    $protectedInstallDirectory = Join-Path $testRoot 'protected\Programs\Switchgear'
    $protectedProfileDataDirectory = Join-Path $testRoot 'protected\Data\Switchgear'
    & $installScript `
        -SourceRoot $projectRoot `
        -InstallDirectory $protectedInstallDirectory `
        -ProfileDataDirectory $protectedProfileDataDirectory `
        -SkipPathRegistration `
        -Confirm:$false | Out-Null
    [IO.Directory]::CreateDirectory($protectedProfileDataDirectory) | Out-Null
    [IO.File]::WriteAllText((Join-Path $protectedProfileDataDirectory 'unrelated.txt'), 'must not be deleted')

    Assert-Throws -Message 'Uninstaller accepted Profile-data removal without a valid state marker.' -Action {
        & $uninstallScript `
            -InstallDirectory $protectedInstallDirectory `
            -SkipPathCleanup `
            -RemoveProfileData `
            -Confirm:$false | Out-Null
    }
    Assert-True -Condition (Test-Path -LiteralPath $protectedInstallDirectory -PathType Container) -Message 'Failed Profile-data preflight removed program files.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $protectedProfileDataDirectory 'unrelated.txt') -PathType Leaf) -Message 'Failed Profile-data preflight removed unrelated data.'

    & $uninstallScript `
        -InstallDirectory $protectedInstallDirectory `
        -SkipPathCleanup `
        -Confirm:$false | Out-Null
    Assert-True -Condition (-not (Test-Path -LiteralPath $protectedInstallDirectory)) -Message 'Default uninstall did not remove the protected test installation.'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $protectedProfileDataDirectory 'unrelated.txt') -PathType Leaf) -Message 'Default uninstall removed protected test data.'

    $updateInstallDirectory = Join-Path $testRoot 'update-failure\Programs\Switchgear'
    $updateProfileDataDirectory = Join-Path $testRoot 'update-failure\Data\Switchgear'
    & $installScript `
        -SourceRoot $projectRoot `
        -InstallDirectory $updateInstallDirectory `
        -ProfileDataDirectory $updateProfileDataDirectory `
        -SkipPathRegistration `
        -Confirm:$false | Out-Null
    $installedVersionPath = Join-Path $updateInstallDirectory 'VERSION'
    $installedVersionBefore = [IO.File]::ReadAllText($installedVersionPath)
    $brokenSourceRoot = Join-Path $testRoot 'broken-source'
    [IO.Directory]::CreateDirectory($brokenSourceRoot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $brokenSourceRoot 'VERSION'), 'broken-test-version')

    Assert-Throws -Message 'Broken update source unexpectedly succeeded.' -Action {
        & $installScript `
            -SourceRoot $brokenSourceRoot `
            -InstallDirectory $updateInstallDirectory `
            -ProfileDataDirectory $updateProfileDataDirectory `
            -Update `
            -SkipPathRegistration `
            -Confirm:$false | Out-Null
    }
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $updateInstallDirectory '.switchgear-install.json') -PathType Leaf) -Message 'Failed update damaged the install marker.'
    Assert-True -Condition ([IO.File]::ReadAllText($installedVersionPath).Equals($installedVersionBefore)) -Message 'Failed update changed the installed version.'

    & $uninstallScript `
        -InstallDirectory $updateInstallDirectory `
        -SkipPathCleanup `
        -Confirm:$false | Out-Null

    $pathAfter = [Environment]::GetEnvironmentVariable('Path', 'User')
    Assert-True -Condition ([string]::Equals([string]$pathBefore, [string]$pathAfter, [StringComparison]::Ordinal)) -Message 'Safety tests changed the real user PATH.'

    Write-Output 'PASS: CMD lifecycle, explicit temp-data removal, data-delete refusal, failed-update preservation, synthetic PATH matching, and real PATH isolation passed.'
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
