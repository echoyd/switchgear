[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string]$Command = 'help',

    [Parameter(Position = 1)]
    [string]$ProfileName,

    [Parameter(Position = 2)]
    [string]$Surface,

    [ValidateSet('Dual', 'Triple')]
    [string]$Mode = 'Dual',

    [ValidateSet('CLI', 'VSCode', 'Both')]
    [string]$Targets,

    [ValidateSet('CLI', 'VSCode')]
    [string]$DefaultTarget,

    [string]$CodexHome,

    [string]$Workspace,

    [string]$OutputDirectory,

    [string]$CodexPath,

    [string]$VsCodePath,

    [ValidateSet('None', 'CLI', 'VSCode', 'Both')]
    [string]$DesktopShortcut = 'None',

    [string]$DesktopDirectory,

    [string]$StatePath,

    [switch]$SkipAuthCheck,

    [switch]$Force,

    [switch]$Yes,

    [switch]$Json,

    [switch]$PassThru,

    [switch]$ThrowOnError,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$ForwardArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:CoreRoot = $PSScriptRoot
$script:LauncherGenerator = Join-Path $script:CoreRoot 'lib\New-SwitchgearProfileLaunchers.ps1'
$script:HealthChecker = Join-Path $script:CoreRoot 'lib\Test-SwitchgearProfile.ps1'
$script:RootCmdlet = $PSCmdlet
$script:InvocationParameters = @{}
foreach ($parameterKey in $PSBoundParameters.Keys) {
    $script:InvocationParameters[$parameterKey] = $PSBoundParameters[$parameterKey]
}

function Get-DefaultDataRoot {
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Windows LocalApplicationData could not be resolved.'
    }
    return Join-Path $localData 'Switchgear'
}

function Resolve-FullPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$MustExist,

        [switch]$MustBeDirectory
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $fullPath = [IO.Path]::GetFullPath($expanded)

    if ($MustExist -and -not (Test-Path -LiteralPath $fullPath)) {
        throw "Path does not exist: $fullPath"
    }

    if ($MustBeDirectory -and -not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Path is not a directory: $fullPath"
    }

    return $fullPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-ResolvedStatePath {
    param([string]$RequestedPath)

    if ($RequestedPath) {
        return Resolve-FullPath -Path $RequestedPath
    }

    return Join-Path (Get-DefaultDataRoot) 'state.json'
}

function New-EmptyState {
    return [pscustomobject]@{
        schemaVersion = 1
        product = 'Switchgear'
        profiles = @()
    }
}

function Read-SwitchgearState {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-EmptyState
    }

    $raw = [IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Switchgear state is empty: $Path"
    }

    try {
        $state = $raw | ConvertFrom-Json
    }
    catch {
        throw "Switchgear state is not valid JSON: $Path"
    }

    if ($state.product -ne 'Switchgear' -or $state.schemaVersion -ne 1) {
        throw "Unsupported Switchgear state format: $Path"
    }

    if ($null -eq $state.profiles) {
        $state.profiles = @()
    }

    return $state
}

function Save-SwitchgearState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $directory = Split-Path -Parent $Path
    [IO.Directory]::CreateDirectory($directory) | Out-Null
    $temporaryPath = Join-Path $directory ([IO.Path]::GetRandomFileName())
    $utf8NoBom = New-Object Text.UTF8Encoding($false)

    try {
        $jsonText = $State | ConvertTo-Json -Depth 8
        [IO.File]::WriteAllText($temporaryPath, ($jsonText + [Environment]::NewLine), $utf8NoBom)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-Profile {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return @($State.profiles | Where-Object { $_.name -eq $Name }) | Select-Object -First 1
}

function Convert-TargetSelection {
    param([Parameter(Mandatory = $true)][string]$Selection)

    switch ($Selection) {
        'CLI' { return @('CLI') }
        'VSCode' { return @('VSCode') }
        'Both' { return @('CLI', 'VSCode') }
        default { throw "Unsupported target selection: $Selection" }
    }
}

function Convert-ShortcutSelection {
    param([Parameter(Mandatory = $true)][string]$Selection)

    switch ($Selection) {
        'None' { return @() }
        'CLI' { return @('CLI') }
        'VSCode' { return @('VSCode') }
        'Both' { return @('CLI', 'VSCode') }
        default { throw "Unsupported shortcut selection: $Selection" }
    }
}

function Read-Choice {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [Parameter(Mandatory = $true)]
        [string]$Default,

        [Parameter(Mandatory = $true)]
        [string[]]$Allowed
    )

    while ($true) {
        $answer = Read-Host "$Prompt [$Default]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        if ($Allowed -contains $answer) {
            return $answer
        }
        Write-Host "Choose one of: $($Allowed -join ', ')" -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,

        [bool]$Default = $false
    )

    $defaultText = if ($Default) { 'Y/n' } else { 'y/N' }
    while ($true) {
        $answer = Read-Host "$Prompt [$defaultText]"
        if ([string]::IsNullOrWhiteSpace($answer)) {
            return $Default
        }
        if ($answer -match '^(y|yes)$') {
            return $true
        }
        if ($answer -match '^(n|no)$') {
            return $false
        }
        Write-Host 'Enter y or n.' -ForegroundColor Yellow
    }
}

function Write-Banner {
    Write-Host ''
    Write-Host 'SWITCHGEAR' -ForegroundColor Cyan
    Write-Host 'Switch profiles. Keep credentials isolated.'
    Write-Host ''
}

function Write-HelpText {
    Write-Banner
    Write-Host 'Commands'
    Write-Host '  switchgear setup                 Configure the supported dual-account layout'
    Write-Host '  switchgear list                  List locally managed profiles'
    Write-Host '  switchgear B                     Open profile B with its default surface'
    Write-Host '  switchgear B cli                 Open profile B in Codex CLI'
    Write-Host '  switchgear B vscode              Open profile B in VS Code'
    Write-Host '  switchgear doctor B              Check profile B'
    Write-Host ''
    Write-Host 'Switchgear stores paths and launcher metadata only. It never copies credentials.'
}

function New-DesktopShortcut {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ShortcutPath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $shortcutDirectory = Split-Path -Parent $ShortcutPath
    [IO.Directory]::CreateDirectory($shortcutDirectory) | Out-Null
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $null

    try {
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
        $shortcut.Description = $Description
        $shortcut.Save()
    }
    finally {
        if ($shortcut) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut)
        }
        if ($shell) {
            [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell)
        }
    }
}

function Invoke-Setup {
    $resolvedStatePath = Get-ResolvedStatePath -RequestedPath $StatePath
    $dataRoot = Split-Path -Parent $resolvedStatePath

    if (-not $script:InvocationParameters.ContainsKey('Mode')) {
        Write-Banner
        Write-Host 'Account layout'
        Write-Host '  [1] Dual account - supported'
        Write-Host '  [2] Three account - coming later'
        Write-Host ''
        $modeChoice = Read-Choice -Prompt 'Select' -Default '1' -Allowed @('1', '2')
        if ($modeChoice -eq '2') {
            throw 'Three-account setup is planned but not enabled in this version. No changes were made.'
        }
        $script:Mode = 'Dual'
    }

    if ($Mode -eq 'Triple') {
        throw 'Three-account setup is planned but not enabled in this version. No changes were made.'
    }

    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        $enteredName = Read-Host 'Secondary profile label [B]'
        $script:ProfileName = if ([string]::IsNullOrWhiteSpace($enteredName)) { 'B' } else { $enteredName }
    }

    if ($ProfileName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') {
        throw 'ProfileName must use letters, digits, dots, underscores, or hyphens.'
    }

    if (-not $script:InvocationParameters.ContainsKey('Targets')) {
        Write-Host ''
        Write-Host 'Where should this profile be available?'
        Write-Host '  [1] CLI'
        Write-Host '  [2] VS Code'
        Write-Host '  [3] Both'
        Write-Host ''
        $targetChoice = Read-Choice -Prompt 'Select' -Default '3' -Allowed @('1', '2', '3')
        $script:Targets = switch ($targetChoice) {
            '1' { 'CLI' }
            '2' { 'VSCode' }
            '3' { 'Both' }
        }
    }

    $targetList = @(Convert-TargetSelection -Selection $Targets)

    if ([string]::IsNullOrWhiteSpace($Workspace)) {
        $enteredWorkspace = Read-Host "Workspace [$((Get-Location).Path)]"
        $script:Workspace = if ([string]::IsNullOrWhiteSpace($enteredWorkspace)) {
            (Get-Location).Path
        }
        else {
            $enteredWorkspace
        }
    }
    $resolvedWorkspace = Resolve-FullPath -Path $Workspace -MustExist -MustBeDirectory

    if ([string]::IsNullOrWhiteSpace($CodexHome)) {
        $script:CodexHome = Join-Path $dataRoot "profiles\$ProfileName\codex-home"
    }
    $resolvedCodexHome = Resolve-FullPath -Path $CodexHome

    if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
        $script:OutputDirectory = Join-Path $dataRoot "launchers\$ProfileName"
    }
    $resolvedOutputDirectory = Resolve-FullPath -Path $OutputDirectory

    if (-not $script:InvocationParameters.ContainsKey('DefaultTarget')) {
        if ($targetList.Count -eq 1) {
            $script:DefaultTarget = $targetList[0]
        }
        elseif ($Yes -or $WhatIfPreference) {
            $script:DefaultTarget = 'CLI'
        }
        else {
            Write-Host ''
            Write-Host 'Default surface'
            Write-Host '  [1] CLI'
            Write-Host '  [2] VS Code'
            $defaultChoice = Read-Choice -Prompt 'Select' -Default '1' -Allowed @('1', '2')
            $script:DefaultTarget = if ($defaultChoice -eq '1') { 'CLI' } else { 'VSCode' }
        }
    }

    if ($targetList -notcontains $DefaultTarget) {
        throw "DefaultTarget $DefaultTarget is not included in Targets $Targets."
    }

    if (-not $script:InvocationParameters.ContainsKey('DesktopShortcut') -and -not $Yes -and -not $WhatIfPreference) {
        $suggestedShortcut = if ($targetList -contains 'VSCode') { 'VSCode' } else { 'CLI' }
        $suggestedShortcutDisplay = if ($suggestedShortcut -eq 'VSCode') { 'VS Code' } else { 'CLI' }
        if (Read-YesNo -Prompt "Create a desktop shortcut for $suggestedShortcutDisplay" -Default ($suggestedShortcut -eq 'VSCode')) {
            $script:DesktopShortcut = $suggestedShortcut
        }
        else {
            $script:DesktopShortcut = 'None'
        }
    }

    $shortcutTargets = @(Convert-ShortcutSelection -Selection $DesktopShortcut)
    foreach ($shortcutTarget in $shortcutTargets) {
        if ($targetList -notcontains $shortcutTarget) {
            throw "DesktopShortcut requests $shortcutTarget, but that target is not enabled."
        }
    }

    if ($shortcutTargets.Count -gt 0) {
        if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) {
            $script:DesktopDirectory = [Environment]::GetFolderPath('Desktop')
        }
        if ([string]::IsNullOrWhiteSpace($DesktopDirectory)) {
            throw 'The Windows Desktop directory could not be resolved.'
        }
        $resolvedDesktopDirectory = Resolve-FullPath -Path $DesktopDirectory
    }
    else {
        $resolvedDesktopDirectory = $null
    }

    $state = Read-SwitchgearState -Path $resolvedStatePath
    $existingProfile = Get-Profile -State $state -Name $ProfileName
    if ($existingProfile -and -not $Force) {
        throw "Profile $ProfileName already exists in Switchgear state. Use -Force to replace its non-secret metadata and generated launchers."
    }
    $otherProfiles = @($state.profiles | Where-Object { $_.name -ne $ProfileName })
    if ($otherProfiles.Count -gt 0) {
        throw 'This version supports one managed secondary profile. Three-account setup is planned but not enabled.'
    }

    foreach ($shortcutTarget in $shortcutTargets) {
        $plannedShortcutTargetDisplay = if ($shortcutTarget -eq 'VSCode') { 'VS Code' } else { 'CLI' }
        $plannedShortcutPath = Join-Path $resolvedDesktopDirectory "Switchgear $ProfileName - $plannedShortcutTargetDisplay.lnk"
        if ((Test-Path -LiteralPath $plannedShortcutPath) -and -not $Force) {
            throw "Desktop shortcut already exists: $plannedShortcutPath. Use -Force to replace it."
        }
    }

    Write-Banner
    $surfaceDisplay = ($targetList -join ', ').Replace('VSCode', 'VS Code')
    $shortcutDisplay = $DesktopShortcut.Replace('VSCode', 'VS Code')
    Write-Host 'Review'
    Write-Host ("  {0,-11}{1}" -f 'Mode', 'Dual account')
    Write-Host ("  {0,-11}{1}" -f 'Profile', $ProfileName)
    Write-Host ("  {0,-11}{1}" -f 'Surfaces', $surfaceDisplay)
    Write-Host ("  {0,-11}{1}" -f 'Default', $DefaultTarget)
    Write-Host ("  {0,-11}{1}" -f 'Workspace', $resolvedWorkspace)
    Write-Host ("  {0,-11}{1}" -f 'CODEX_HOME', $resolvedCodexHome)
    Write-Host ("  {0,-11}{1}" -f 'State', $resolvedStatePath)
    Write-Host ("  {0,-11}{1}" -f 'Shortcuts', $shortcutDisplay)
    Write-Host '  Credentials are never copied or inspected.'
    Write-Host ''

    if (-not $Yes -and -not $WhatIfPreference) {
        if (-not (Read-YesNo -Prompt 'Apply this setup' -Default $false)) {
            Write-Host 'CANCELLED - no changes were made.' -ForegroundColor Yellow
            return
        }
    }

    $generatorParameters = @{
        ProfileName = $ProfileName
        CodexHome = $resolvedCodexHome
        Workspace = $resolvedWorkspace
        OutputDirectory = $resolvedOutputDirectory
        Targets = $targetList
        ConfigureFileCredentialStore = $true
        WhatIf = [bool]$WhatIfPreference
    }
    if ($CodexPath) {
        $generatorParameters.CodexPath = $CodexPath
    }
    if ($VsCodePath) {
        $generatorParameters.VsCodePath = $VsCodePath
    }
    if ($Force) {
        $generatorParameters.Force = $true
    }

    $generated = & $script:LauncherGenerator @generatorParameters

    $shortcutRecord = [ordered]@{
        CLI = $null
        VSCode = $null
    }

    foreach ($shortcutTarget in $shortcutTargets) {
        $launcherPath = if ($shortcutTarget -eq 'CLI') {
            $generated.Launchers.CLI
        }
        else {
            $generated.Launchers.VSCode
        }
        $shortcutTargetDisplay = if ($shortcutTarget -eq 'VSCode') { 'VS Code' } else { 'CLI' }
        $shortcutPath = Join-Path $resolvedDesktopDirectory "Switchgear $ProfileName - $shortcutTargetDisplay.lnk"
        $shortcutRecord[$shortcutTarget] = $shortcutPath

        if ($script:RootCmdlet.ShouldProcess($shortcutPath, "Create $shortcutTarget desktop shortcut")) {
            New-DesktopShortcut -ShortcutPath $shortcutPath -TargetPath $launcherPath -Description "Open Codex profile $ProfileName in $shortcutTargetDisplay with Switchgear"
        }
    }

    $profileRecord = [pscustomobject][ordered]@{
        name = $ProfileName
        mode = 'Dual'
        codexHome = $resolvedCodexHome
        workspace = $resolvedWorkspace
        targets = $targetList
        defaultTarget = $DefaultTarget
        launchers = [pscustomobject][ordered]@{
            CLI = $generated.Launchers.CLI
            VSCode = $generated.Launchers.VSCode
        }
        executables = [pscustomobject][ordered]@{
            CLI = $generated.Executables.CLI
            VSCode = $generated.Executables.VSCode
        }
        desktopShortcuts = [pscustomobject]$shortcutRecord
        updatedAt = [DateTimeOffset]::Now.ToString('o')
    }

    if (-not $WhatIfPreference) {
        $remainingProfiles = @($state.profiles | Where-Object { $_.name -ne $ProfileName })
        $state.profiles = @($remainingProfiles + $profileRecord)

        if ($script:RootCmdlet.ShouldProcess($resolvedStatePath, 'Write non-secret Switchgear profile metadata')) {
            Save-SwitchgearState -State $state -Path $resolvedStatePath
        }
    }

    if ($WhatIfPreference) {
        Write-Host 'PREVIEW - no changes were made.' -ForegroundColor Yellow
    }
    else {
        Write-Host 'READY' -ForegroundColor Green
        Write-Host "  switchgear $ProfileName    (default: $($DefaultTarget.ToLowerInvariant()))"
        foreach ($target in $targetList) {
            Write-Host "  switchgear $ProfileName $($target.ToLowerInvariant())"
        }
        Write-Host "  switchgear doctor $ProfileName"
    }

    $result = [pscustomobject]@{
        Status = if ($WhatIfPreference) { 'Preview' } else { 'Ready' }
        Profile = $profileRecord
        StatePath = $resolvedStatePath
    }
    if ($Json) {
        $result | ConvertTo-Json -Depth 8
    }
    elseif ($PassThru) {
        return $result
    }
}

function Invoke-ListProfiles {
    $resolvedStatePath = Get-ResolvedStatePath -RequestedPath $StatePath
    $state = Read-SwitchgearState -Path $resolvedStatePath
    $profiles = @($state.profiles)

    if ($Json) {
        [pscustomobject]@{
            product = 'Switchgear'
            statePath = $resolvedStatePath
            profiles = $profiles
        } | ConvertTo-Json -Depth 8
        return
    }

    if ($profiles.Count -eq 0) {
        Write-Host 'No Switchgear profiles are configured.'
        Write-Host 'Run: switchgear setup'
        return
    }

    $profiles |
        Select-Object name, defaultTarget, @{ Name = 'targets'; Expression = { $_.targets -join ', ' } }, workspace |
        Format-Table -AutoSize
}

function Invoke-Doctor {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        throw 'Specify a profile: switchgear doctor B'
    }

    $resolvedStatePath = Get-ResolvedStatePath -RequestedPath $StatePath
    $state = Read-SwitchgearState -Path $resolvedStatePath
    $profile = Get-Profile -State $state -Name $ProfileName
    if (-not $profile) {
        throw "Switchgear profile not found: $ProfileName"
    }

    $doctorTargets = if ($Surface) {
        if ($Surface -notin @('cli', 'vscode')) {
            throw 'Doctor surface must be cli or vscode.'
        }
        @($(if ($Surface -eq 'cli') { 'CLI' } else { 'VSCode' }))
    }
    else {
        @($profile.targets)
    }

    $healthParameters = @{
        CodexHome = $profile.codexHome
        Workspace = $profile.workspace
        Targets = $doctorTargets
        SkipAuthCheck = [bool]$SkipAuthCheck
        AsJson = [bool]$Json
    }
    if ($profile.PSObject.Properties.Name -contains 'executables') {
        if ($profile.executables.CLI) {
            $healthParameters.CodexPath = $profile.executables.CLI
        }
        if ($profile.executables.VSCode) {
            $healthParameters.VsCodePath = $profile.executables.VSCode
        }
    }
    & $script:HealthChecker @healthParameters
}

function Invoke-OpenProfile {
    if ([string]::IsNullOrWhiteSpace($ProfileName)) {
        throw 'Specify a profile: switchgear B cli'
    }

    $resolvedStatePath = Get-ResolvedStatePath -RequestedPath $StatePath
    $state = Read-SwitchgearState -Path $resolvedStatePath
    $profile = Get-Profile -State $state -Name $ProfileName
    if (-not $profile) {
        throw "Switchgear profile not found: $ProfileName"
    }

    $requestedTarget = if ([string]::IsNullOrWhiteSpace($Surface)) {
        $profile.defaultTarget
    }
    elseif ($Surface -eq 'cli') {
        'CLI'
    }
    elseif ($Surface -eq 'vscode') {
        'VSCode'
    }
    else {
        throw 'Surface must be cli or vscode.'
    }

    if (@($profile.targets) -notcontains $requestedTarget) {
        throw "Profile $ProfileName is not configured for $requestedTarget."
    }

    $launcherPath = $profile.launchers.$requestedTarget
    if ([string]::IsNullOrWhiteSpace($launcherPath) -or -not (Test-Path -LiteralPath $launcherPath -PathType Leaf)) {
        throw "The $requestedTarget launcher is missing. Run setup again for profile $ProfileName."
    }

    if ($requestedTarget -eq 'VSCode' -and $ForwardArguments.Count -gt 0) {
        throw 'VS Code launch does not accept forwarded Codex CLI arguments.'
    }

    & $launcherPath @ForwardArguments
    if ($null -ne $LASTEXITCODE) {
        exit $LASTEXITCODE
    }
}

if (-not (Test-Path -LiteralPath $script:LauncherGenerator -PathType Leaf)) {
    throw "Switchgear launcher engine is missing: $script:LauncherGenerator"
}
if (-not (Test-Path -LiteralPath $script:HealthChecker -PathType Leaf)) {
    throw "Switchgear health engine is missing: $script:HealthChecker"
}

$knownCommands = @('help', '--help', '-h', 'setup', 'list', 'doctor', 'open')
$normalizedCommand = $Command.ToLowerInvariant()

if ($knownCommands -notcontains $normalizedCommand) {
    $compactProfile = $Command
    $compactSurface = $ProfileName
    $forwardPrefix = @()
    if (-not [string]::IsNullOrWhiteSpace($Surface)) {
        $forwardPrefix += $Surface
    }
    $script:ForwardArguments = @($forwardPrefix + $ForwardArguments)
    $script:ProfileName = $compactProfile
    $script:Surface = $compactSurface
    $normalizedCommand = 'open'
}

try {
    switch ($normalizedCommand) {
        'help' { Write-HelpText }
        '--help' { Write-HelpText }
        '-h' { Write-HelpText }
        'setup' { Invoke-Setup }
        'list' { Invoke-ListProfiles }
        'doctor' { Invoke-Doctor }
        'open' { Invoke-OpenProfile }
        default { throw "Unsupported command: $Command" }
    }
}
catch {
    if ($ThrowOnError) {
        throw
    }
    Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
