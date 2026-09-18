Set-StrictMode -Version Latest

function Resolve-SwitchgearInstallerPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    return [IO.Path]::GetFullPath($expanded).TrimEnd(
        [IO.Path]::DirectorySeparatorChar,
        [IO.Path]::AltDirectorySeparatorChar
    )
}

function Assert-SwitchgearSafeDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Purpose
    )

    $resolved = Resolve-SwitchgearInstallerPath -Path $Path
    $root = [IO.Path]::GetPathRoot($resolved).TrimEnd('\', '/')
    if ($resolved.TrimEnd('\', '/').Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Purpose cannot be a drive root: $resolved"
    }

    $relative = $resolved.Substring([IO.Path]::GetPathRoot($resolved).Length).Trim('\', '/')
    $segments = @($relative -split '[\\/]' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments.Count -lt 2) {
        throw "$Purpose is too broad. Choose a dedicated product directory: $resolved"
    }

    return $resolved
}

function Test-SwitchgearPathEquals {
    param(
        [Parameter(Mandatory = $true)][string]$Left,
        [Parameter(Mandatory = $true)][string]$Right
    )

    $leftResolved = Resolve-SwitchgearInstallerPath -Path $Left
    $rightResolved = Resolve-SwitchgearInstallerPath -Path $Right
    return $leftResolved.Equals($rightResolved, [StringComparison]::OrdinalIgnoreCase)
}

function Get-SwitchgearDefaultInstallDirectory {
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Windows LocalApplicationData could not be resolved.'
    }
    return Join-Path $localData 'Programs\Switchgear'
}

function Get-SwitchgearDefaultProfileDataDirectory {
    $localData = [Environment]::GetFolderPath('LocalApplicationData')
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'Windows LocalApplicationData could not be resolved.'
    }
    return Join-Path $localData 'Switchgear'
}

function Get-SwitchgearUserPath {
    $value = [Environment]::GetEnvironmentVariable('Path', 'User')
    if ($null -eq $value) {
        return ''
    }
    return [string]$value
}

function Split-SwitchgearPathEntries {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return @()
    }

    return @($Value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Test-SwitchgearPathContains {
    param(
        [AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][string]$Entry
    )

    $resolvedEntry = Resolve-SwitchgearInstallerPath -Path $Entry
    foreach ($candidate in @(Split-SwitchgearPathEntries -Value $Value)) {
        try {
            if ((Resolve-SwitchgearInstallerPath -Path $candidate).Equals($resolvedEntry, [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
        catch {
            if ($candidate.TrimEnd('\', '/').Equals($Entry.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }
    }
    return $false
}

function Add-SwitchgearUserPathEntry {
    param([Parameter(Mandatory = $true)][string]$Entry)

    $resolvedEntry = Resolve-SwitchgearInstallerPath -Path $Entry
    $current = Get-SwitchgearUserPath
    if (Test-SwitchgearPathContains -Value $current -Entry $resolvedEntry) {
        return $false
    }

    $entries = @(Split-SwitchgearPathEntries -Value $current)
    $updated = (@($entries + $resolvedEntry) -join ';')
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    return $true
}

function Remove-SwitchgearUserPathEntry {
    param([Parameter(Mandatory = $true)][string]$Entry)

    $resolvedEntry = Resolve-SwitchgearInstallerPath -Path $Entry
    $current = Get-SwitchgearUserPath
    $kept = New-Object Collections.Generic.List[string]
    $removed = $false

    foreach ($candidate in @(Split-SwitchgearPathEntries -Value $current)) {
        $isMatch = $false
        try {
            $isMatch = (Resolve-SwitchgearInstallerPath -Path $candidate).Equals($resolvedEntry, [StringComparison]::OrdinalIgnoreCase)
        }
        catch {
            $isMatch = $candidate.TrimEnd('\', '/').Equals($resolvedEntry.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)
        }

        if ($isMatch) {
            $removed = $true
        }
        else {
            $kept.Add($candidate)
        }
    }

    if ($removed) {
        [Environment]::SetEnvironmentVariable('Path', ($kept -join ';'), 'User')
    }
    return $removed
}

function Read-SwitchgearInstallManifest {
    param([Parameter(Mandatory = $true)][string]$InstallDirectory)

    $manifestPath = Join-Path $InstallDirectory '.switchgear-install.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Switchgear install marker is missing: $manifestPath"
    }

    try {
        $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    }
    catch {
        throw "Switchgear install marker is invalid: $manifestPath"
    }

    if ($manifest.product -ne 'Switchgear' -or $manifest.schemaVersion -ne 1) {
        throw "Unsupported Switchgear install marker: $manifestPath"
    }
    if (-not (Test-SwitchgearPathEquals -Left $manifest.installDirectory -Right $InstallDirectory)) {
        throw 'The install marker does not belong to the requested installation directory.'
    }

    return $manifest
}
