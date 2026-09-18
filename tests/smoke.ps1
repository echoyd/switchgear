[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$coreRoot = Join-Path $projectRoot 'core'
$coreScript = Join-Path $coreRoot 'Switchgear.ps1'
$wrapperScript = Join-Path $projectRoot 'switchgear.cmd'
$setupScript = Join-Path $coreRoot 'lib\New-SwitchgearProfileLaunchers.ps1'
$healthScript = Join-Path $coreRoot 'lib\Test-SwitchgearProfile.ps1'
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
$testRoot = Join-Path $tempRoot ("switchgear-{0}" -f [Guid]::NewGuid().ToString('N'))

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Throws {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$Action,

        [Parameter(Mandatory = $true)]
        [string]$Message
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
    $workspace = Join-Path $testRoot 'workspace'
    $profile = Join-Path $testRoot 'profiles\secondary'
    $launchers = Join-Path $testRoot 'launchers'
    [IO.Directory]::CreateDirectory($workspace) | Out-Null
    [IO.File]::WriteAllText(
        (Join-Path $workspace 'AGENTS.md'),
        ('# Test project' + [Environment]::NewLine),
        (New-Object Text.UTF8Encoding($false))
    )
    $fakeCodex = Join-Path $testRoot 'fake-codex.cmd'
    $fakeCodexLog = Join-Path $testRoot 'fake-codex.log'
    $fakeCodexContent = @(
        '@echo off'
        ('echo CODEX_HOME=%CODEX_HOME%>"{0}"' -f $fakeCodexLog)
        ('echo WORKSPACE=%CD%>>"{0}"' -f $fakeCodexLog)
        ('echo ARGS=%*>>"{0}"' -f $fakeCodexLog)
        'exit /b 0'
    )
    [IO.File]::WriteAllLines($fakeCodex, $fakeCodexContent, (New-Object Text.ASCIIEncoding))

    $previewParameters = @{
        ProfileName = 'Secondary'
        CodexHome = $profile
        Workspace = $workspace
        OutputDirectory = $launchers
        Targets = @('CLI', 'VSCode')
        CodexPath = $fakeCodex
        VsCodePath = $env:ComSpec
        ConfigureFileCredentialStore = $true
        WhatIf = $true
    }
    $preview = & $setupScript @previewParameters

    Assert-True -Condition (-not (Test-Path -LiteralPath $profile)) -Message 'WhatIf created the profile directory.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $launchers)) -Message 'WhatIf created the launcher directory.'
    Assert-True -Condition ([bool]$preview) -Message 'WhatIf did not return a plan object.'
    Assert-True -Condition ($preview.Targets.Count -eq 2) -Message 'WhatIf did not plan both targets.'

    $createParameters = $previewParameters.Clone()
    $createParameters.Remove('WhatIf')
    $created = & $setupScript @createParameters

    $cliLauncherPath = $created.Launchers.CLI
    $vsCodeLauncherPath = $created.Launchers.VSCode
    $configPath = Join-Path $profile 'config.toml'
    Assert-True -Condition (Test-Path -LiteralPath $cliLauncherPath -PathType Leaf) -Message 'CLI launcher was not created.'
    Assert-True -Condition (Test-Path -LiteralPath $vsCodeLauncherPath -PathType Leaf) -Message 'VS Code launcher was not created.'
    Assert-True -Condition (Test-Path -LiteralPath $configPath -PathType Leaf) -Message 'Minimal config.toml was not created.'

    $cliLauncherText = [IO.File]::ReadAllText($cliLauncherPath)
    $vsCodeLauncherText = [IO.File]::ReadAllText($vsCodeLauncherPath)
    $configText = [IO.File]::ReadAllText($configPath)
    Assert-True -Condition ($cliLauncherText.Contains('set "CODEX_HOME=')) -Message 'CLI launcher does not set CODEX_HOME.'
    Assert-True -Condition ($cliLauncherText.Contains('cd /d "%CODEX_WORKSPACE%"')) -Message 'CLI launcher does not enter the selected workspace.'
    Assert-True -Condition ($cliLauncherText.Contains('call "%CODEX_EXE%" %*')) -Message 'CLI launcher does not forward Codex arguments.'
    Assert-True -Condition (-not $cliLauncherText.Contains('Code.exe')) -Message 'CLI launcher incorrectly depends on VS Code process state.'
    Assert-True -Condition ($vsCodeLauncherText.Contains('tasklist') -and $vsCodeLauncherText.Contains('IMAGENAME eq Code.exe')) -Message 'VS Code launcher does not guard against process reuse.'
    Assert-True -Condition ($vsCodeLauncherText.Contains('set "CODEX_HOME=')) -Message 'VS Code launcher does not set CODEX_HOME.'
    Assert-True -Condition (-not $cliLauncherText.Contains('auth.json') -and -not $vsCodeLauncherText.Contains('auth.json')) -Message 'A launcher contains credential-file handling.'
    Assert-True -Condition ($configText.Contains('cli_auth_credentials_store = "file"')) -Message 'Credential store is not explicitly file-based.'

    $healthParameters = @{
        CodexHome = $profile
        Workspace = $workspace
        Targets = @('CLI')
        CodexPath = $env:ComSpec
        SkipAuthCheck = $true
        AsJson = $true
    }
    $jsonOutput = & $healthScript @healthParameters
    $report = $jsonOutput | ConvertFrom-Json
    Assert-True -Condition $report.Healthy -Message 'Health report contains a blocking failure.'
    Assert-True -Condition ($report.Product -eq 'Switchgear') -Message 'Health report uses the wrong product identity.'
    Assert-True -Condition ($report.Targets.Count -eq 1 -and $report.Targets[0] -eq 'CLI') -Message 'Health report does not preserve selected targets.'

    $cliOnlyParameters = @{
        ProfileName = 'CliOnly'
        CodexHome = (Join-Path $testRoot 'profiles\cli-only')
        Workspace = $workspace
        OutputDirectory = (Join-Path $testRoot 'cli-only')
        Targets = @('CLI')
        CodexPath = $env:ComSpec
        VsCodePath = (Join-Path $testRoot 'missing-code.exe')
    }
    $cliOnly = & $setupScript @cliOnlyParameters
    Assert-True -Condition (Test-Path -LiteralPath $cliOnly.Launchers.CLI -PathType Leaf) -Message 'CLI-only generation failed.'
    Assert-True -Condition ($null -eq $cliOnly.Launchers.VSCode) -Message 'CLI-only generation created a VS Code launcher.'

    Assert-Throws -Message 'Setup accepted a CodexHome inside the shared workspace.' -Action {
        $unsafeParameters = @{
            ProfileName = 'Unsafe'
            CodexHome = (Join-Path $workspace '.codex-secondary')
            Workspace = $workspace
            OutputDirectory = $launchers
            Targets = @('CLI')
            CodexPath = $env:ComSpec
            WhatIf = $true
        }
        & $setupScript @unsafeParameters | Out-Null
    }

    $nestedWorkspace = Join-Path $testRoot 'profiles-parent\workspace'
    [IO.Directory]::CreateDirectory($nestedWorkspace) | Out-Null
    Assert-Throws -Message 'Setup accepted a shared workspace inside CodexHome.' -Action {
        $unsafeParentParameters = @{
            ProfileName = 'UnsafeParent'
            CodexHome = (Split-Path -Parent $nestedWorkspace)
            Workspace = $nestedWorkspace
            OutputDirectory = $launchers
            Targets = @('CLI')
            CodexPath = $env:ComSpec
            WhatIf = $true
        }
        & $setupScript @unsafeParentParameters | Out-Null
    }

    $existingProfile = Join-Path $testRoot 'profiles\existing'
    [IO.Directory]::CreateDirectory($existingProfile) | Out-Null
    $existingConfig = Join-Path $existingProfile 'config.toml'
    $existingConfigText = 'model = "example"' + [Environment]::NewLine
    [IO.File]::WriteAllText($existingConfig, $existingConfigText, (New-Object Text.UTF8Encoding($false)))
    $existingParameters = @{
        ProfileName = 'Existing'
        CodexHome = $existingProfile
        Workspace = $workspace
        OutputDirectory = $launchers
        Targets = @('CLI')
        CodexPath = $env:ComSpec
        ConfigureFileCredentialStore = $true
    }
    $existingResult = & $setupScript @existingParameters
    Assert-True -Condition ($existingResult.ConfigDisposition -eq 'ExistingPreserved') -Message 'Existing config.toml was not reported as preserved.'
    Assert-True -Condition ([IO.File]::ReadAllText($existingConfig).Equals($existingConfigText)) -Message 'Existing config.toml changed.'

    $coreStatePath = Join-Path $testRoot 'core-state\state.json'
    $coreProfilePath = Join-Path $testRoot 'core-profile\codex-home'
    $coreLauncherPath = Join-Path $testRoot 'core-launchers'
    $corePreviewParameters = @{
        Command = 'setup'
        ProfileName = 'B'
        Mode = 'Dual'
        Targets = 'Both'
        DefaultTarget = 'CLI'
        CodexHome = $coreProfilePath
        Workspace = $workspace
        OutputDirectory = $coreLauncherPath
        CodexPath = $fakeCodex
        VsCodePath = $env:ComSpec
        DesktopShortcut = 'None'
        StatePath = $coreStatePath
        Yes = $true
        PassThru = $true
        WhatIf = $true
        ThrowOnError = $true
    }
    $corePreview = & $coreScript @corePreviewParameters
    Assert-True -Condition ($corePreview.Status -eq 'Preview') -Message 'Core setup did not return preview status.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $coreStatePath)) -Message 'Core WhatIf wrote state.'
    Assert-True -Condition (-not (Test-Path -LiteralPath $coreProfilePath)) -Message 'Core WhatIf created CODEX_HOME.'

    $coreCreateParameters = $corePreviewParameters.Clone()
    $coreCreateParameters.Remove('WhatIf')
    $coreCreated = & $coreScript @coreCreateParameters
    Assert-True -Condition ($coreCreated.Status -eq 'Ready') -Message 'Core setup did not finish ready.'
    Assert-True -Condition (Test-Path -LiteralPath $coreStatePath -PathType Leaf) -Message 'Core setup did not create state.'
    Assert-True -Condition (Test-Path -LiteralPath $coreCreated.Profile.launchers.CLI -PathType Leaf) -Message 'Core setup did not create the CLI launcher.'
    Assert-True -Condition (Test-Path -LiteralPath $coreCreated.Profile.launchers.VSCode -PathType Leaf) -Message 'Core setup did not create the VS Code launcher.'

    & $coreScript B cli exec 'hello world' -StatePath $coreStatePath -ThrowOnError
    Assert-True -Condition (Test-Path -LiteralPath $fakeCodexLog -PathType Leaf) -Message 'Compact CLI open did not invoke the configured Codex executable.'
    $fakeRun = [IO.File]::ReadAllText($fakeCodexLog)
    Assert-True -Condition ($fakeRun.Contains("CODEX_HOME=$coreProfilePath")) -Message 'Compact CLI open used the wrong CODEX_HOME.'
    Assert-True -Condition ($fakeRun.Contains("WORKSPACE=$workspace")) -Message 'Compact CLI open used the wrong workspace.'
    Assert-True -Condition ($fakeRun.Contains('ARGS=exec "hello world"')) -Message 'Compact CLI open did not forward arguments.'

    $listParameters = @{
        Command = 'list'
        StatePath = $coreStatePath
        Json = $true
        ThrowOnError = $true
    }
    $listReport = (& $coreScript @listParameters) | ConvertFrom-Json
    Assert-True -Condition ($listReport.profiles.Count -eq 1) -Message 'Core list did not return one profile.'
    Assert-True -Condition ($listReport.profiles[0].name -eq 'B') -Message 'Core list returned the wrong profile.'

    $doctorParameters = @{
        Command = 'doctor'
        ProfileName = 'B'
        StatePath = $coreStatePath
        SkipAuthCheck = $true
        Json = $true
        ThrowOnError = $true
    }
    $doctorReport = (& $coreScript @doctorParameters) | ConvertFrom-Json
    Assert-True -Condition $doctorReport.Healthy -Message 'Core doctor reported a blocking failure.'

    $stateText = [IO.File]::ReadAllText($coreStatePath)
    Assert-True -Condition ($stateText -notmatch '(?i)token|cookie|password|email|auth\.json') -Message 'Core state contains a credential-like field.'

    $shortcutStatePath = Join-Path $testRoot 'shortcut-state\state.json'
    $shortcutDesktopPath = Join-Path $testRoot 'desktop'
    $shortcutParameters = @{
        Command = 'setup'
        ProfileName = 'Shortcut'
        Mode = 'Dual'
        Targets = 'Both'
        DefaultTarget = 'CLI'
        CodexHome = (Join-Path $testRoot 'shortcut-profile\codex-home')
        Workspace = $workspace
        OutputDirectory = (Join-Path $testRoot 'shortcut-launchers')
        CodexPath = $env:ComSpec
        VsCodePath = $env:ComSpec
        DesktopShortcut = 'VSCode'
        DesktopDirectory = $shortcutDesktopPath
        StatePath = $shortcutStatePath
        Yes = $true
        PassThru = $true
        ThrowOnError = $true
    }
    $shortcutCreated = & $coreScript @shortcutParameters
    Assert-True -Condition (Test-Path -LiteralPath $shortcutCreated.Profile.desktopShortcuts.VSCode -PathType Leaf) -Message 'Core setup did not create the requested VS Code shortcut.'

    Assert-Throws -Message 'Dual-account mode accepted a second managed profile.' -Action {
        $secondProfileParameters = @{
            Command = 'setup'
            ProfileName = 'C'
            Mode = 'Dual'
            Targets = 'CLI'
            DefaultTarget = 'CLI'
            CodexHome = (Join-Path $testRoot 'second-profile\codex-home')
            Workspace = $workspace
            OutputDirectory = (Join-Path $testRoot 'second-launchers')
            CodexPath = $env:ComSpec
            DesktopShortcut = 'None'
            StatePath = $coreStatePath
            Yes = $true
            ThrowOnError = $true
        }
        & $coreScript @secondProfileParameters | Out-Null
    }

    Assert-Throws -Message 'Core setup accepted unsupported three-account mode.' -Action {
        $tripleParameters = @{
            Command = 'setup'
            Mode = 'Triple'
            StatePath = (Join-Path $testRoot 'triple-state\state.json')
            Yes = $true
            ThrowOnError = $true
        }
        & $coreScript @tripleParameters | Out-Null
    }

    $wrapperStatePath = Join-Path $testRoot 'wrapper-state\state.json'
    $wrapperProfilePath = Join-Path $testRoot 'wrapper-profile\codex-home'
    $wrapperLaunchers = Join-Path $testRoot 'wrapper-launchers'
    $wrapperOutput = & $wrapperScript setup Wrapper -Mode Dual -Targets CLI -DefaultTarget CLI -CodexHome $wrapperProfilePath -Workspace $workspace -OutputDirectory $wrapperLaunchers -CodexPath $env:ComSpec -DesktopShortcut None -StatePath $wrapperStatePath -Yes 2>&1
    Assert-True -Condition ($LASTEXITCODE -eq 0) -Message "Root switchgear.cmd failed: $($wrapperOutput -join ' ')"
    Assert-True -Condition (Test-Path -LiteralPath $wrapperStatePath -PathType Leaf) -Message 'Root switchgear.cmd did not create state.'

    $setupSource = [IO.File]::ReadAllText($setupScript)
    $healthSource = [IO.File]::ReadAllText($healthScript)
    $coreSource = [IO.File]::ReadAllText($coreScript)
    Assert-True -Condition (-not $setupSource.Contains('auth.json')) -Message 'Setup script contains auth.json handling.'
    Assert-True -Condition (-not $healthSource.Contains('auth.json')) -Message 'Health script contains auth.json handling.'
    Assert-True -Condition (-not $coreSource.Contains('auth.json')) -Message 'Core script contains auth.json handling.'
    Assert-True -Condition (-not $coreSource.Contains('skill\profile-switchgear')) -Message 'Core script depends on the companion Skill.'

    Write-Output 'PASS: core setup/list/doctor, dual launchers, shortcut creation, WhatIf, isolation, config preservation, and credential boundaries passed.'
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
