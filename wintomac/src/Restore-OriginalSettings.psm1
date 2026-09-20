# Restore-OriginalSettings.psm1 — Revert Windows settings to the state
# captured by Backup-CurrentSettings.
#
# Reads the JSON backup at $env:APPDATA\WinToMac\backup.json, iterates
# every registry entry, and writes the original value back. Values that
# were $null (absent before the theme was applied) are removed so the
# system returns to a clean state.
#
# Dependencies (loaded as NestedModules in the same manifest):
#   Backup-CurrentSettings.psm1 — Get-BackupKeyManifest
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Write-RegistryValue — Set or remove a single registry value
# ---------------------------------------------------------------------------

function Write-RegistryValue {
    <#
    .SYNOPSIS
        Writes a value to the registry, or removes it if the value is $null.

    .DESCRIPTION
        Ensures the parent key exists before writing. When the value is $null,
        the property is removed via Remove-ItemProperty. Binary values are
        decoded from Base64 before writing. Supports DWord, String,
        ExpandString, and Binary types.

    .PARAMETER Path
        The registry key path (e.g., HKCU:\...).

    .PARAMETER ValueName
        The name of the value to set or remove.

    .PARAMETER Value
        The value to write, or $null to remove the property.

    .PARAMETER Type
        The registry value type: DWord, String, ExpandString, or Binary.

    .OUTPUTS
        PSCustomObject with Success (bool) and Action (string: Set, Remove,
        Skip).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ValueName,

        [Parameter()]
        $Value,

        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    try {
        if ($null -eq $Value) {
            # Value was absent before — remove it if it exists now.
            if (Test-Path -Path $Path) {
                $existing = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction SilentlyContinue
                if ($null -ne $existing) {
                    if ($PSCmdlet.ShouldProcess("$Path -> $ValueName", 'Remove registry value')) {
                        Remove-ItemProperty -Path $Path -Name $ValueName -Force -ErrorAction Stop
                    }
                    return [PSCustomObject]@{ Success = $true; Action = 'Remove' }
                }
            }
            return [PSCustomObject]@{ Success = $true; Action = 'Skip' }
        }

        # Ensure the parent key exists.
        if (-not (Test-Path -Path $Path)) {
            if ($PSCmdlet.ShouldProcess($Path, 'Create registry key')) {
                $null = New-Item -Path $Path -Force
            }
        }

        # Map the type string to the RegistryValueKind used by
        # Set-ItemProperty / New-ItemProperty.
        switch ($Type) {
            'DWord' {
                if ($PSCmdlet.ShouldProcess("$Path\$ValueName", "Set to $Value (DWord)")) {
                    Set-ItemProperty -Path $Path -Name $ValueName -Value ([int]$Value) -Type DWord -Force
                }
            }
            'String' {
                if ($PSCmdlet.ShouldProcess("$Path\$ValueName", "Set to $Value (String)")) {
                    Set-ItemProperty -Path $Path -Name $ValueName -Value ([string]$Value) -Type String -Force
                }
            }
            'ExpandString' {
                if ($PSCmdlet.ShouldProcess("$Path\$ValueName", "Set to $Value (ExpandString)")) {
                    Set-ItemProperty -Path $Path -Name $ValueName -Value ([string]$Value) -Type ExpandString -Force
                }
            }
            'Binary' {
                # Value arrives as a hashtable with _type=Binary and Value=base64.
                if ($Value -is [hashtable] -or $Value -is [System.Collections.Specialized.OrderedDictionary]) {
                    $bytes = [Convert]::FromBase64String($Value['Value'])
                }
                elseif ($Value -is [PSCustomObject] -and $Value._type -eq 'Binary') {
                    $bytes = [Convert]::FromBase64String($Value.Value)
                }
                elseif ($Value -is [string]) {
                    # Fallback: raw base64 string.
                    $bytes = [Convert]::FromBase64String($Value)
                }
                else {
                    # Already a byte array (unlikely from JSON, but defensive).
                    $bytes = [byte[]]$Value
                }
                if ($PSCmdlet.ShouldProcess("$Path\$ValueName", 'Set Binary value')) {
                    Set-ItemProperty -Path $Path -Name $ValueName -Value $bytes -Type Binary -Force
                }
            }
            default {
                if ($PSCmdlet.ShouldProcess("$Path\$ValueName", "Set to $Value (String)")) {
                    # Treat unknown types as String.
                    Set-ItemProperty -Path $Path -Name $ValueName -Value ([string]$Value) -Type String -Force
                }
            }
        }

        return [PSCustomObject]@{ Success = $true; Action = 'Set' }
    }
    catch {
        return [PSCustomObject]@{ Success = $false; Action = "Error: $($_.Exception.Message)" }
    }
}

# ---------------------------------------------------------------------------
# Restore-OriginalSettings — Main exported function
# ---------------------------------------------------------------------------

function Restore-OriginalSettings {
    <#
    .SYNOPSIS
        Restores Windows settings from the backup created by
        Backup-CurrentSettings.

    .DESCRIPTION
        Reads and parses $env:APPDATA\WinToMac\backup.json, then iterates
        every Registry entry in the backup:

          - If the stored value is $null the registry property is removed
            (it did not exist before the theme was applied).
          - If the stored value is a binary wrapper (Base64), the bytes are
            decoded and written back with type Binary.
          - Otherwise the value is written with its original type (DWord,
            String, ExpandString) as determined by the static key manifest.

        The wallpaper path and cursor scheme are restored via their registry
        values. The actual SystemParametersInfo P/Invoke to refresh the
        desktop wallpaper is the caller's responsibility.

        Supports -WhatIf: in WhatIf mode every change is reported but no
        registry writes are performed.

    .EXAMPLE
        $result = Restore-OriginalSettings
        if ($result.Success) { Write-Host 'Settings restored.' }

    .EXAMPLE
        Restore-OriginalSettings -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success (bool), RestoredKeys (int),
        Warnings (string[]).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $warnings = [System.Collections.ArrayList]::new()
    $backupPath = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
    $restoredKeys = 0

    Write-Host '[Restore] Reading backup file...' -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Validate and parse the backup file
    # ------------------------------------------------------------------
    if (-not (Test-Path -Path $backupPath -PathType Leaf)) {
        $msg = "Backup file not found at $backupPath. Cannot restore settings."
        Write-Host "[Restore] $msg" -ForegroundColor Red
        return [PSCustomObject]@{
            Success      = $false
            RestoredKeys = 0
            Warnings     = @($msg)
        }
    }

    try {
        $jsonContent = [System.IO.File]::ReadAllText($backupPath, [System.Text.Encoding]::UTF8)
        $backup = $jsonContent | ConvertFrom-Json
    }
    catch {
        $msg = "Failed to parse backup file: $($_.Exception.Message)"
        Write-Host "[Restore] $msg" -ForegroundColor Red
        return [PSCustomObject]@{
            Success      = $false
            RestoredKeys = 0
            Warnings     = @($msg)
        }
    }

    Write-Host "[Restore] Backup version $($backup.Version), created $($backup.Timestamp)" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Build a lookup from the static manifest so we know the type of
    # each key. The composite key format is "Path\ValueName".
    # ------------------------------------------------------------------
    $manifest = Get-BackupKeyManifest
    $typeMap = @{}
    foreach ($entry in $manifest) {
        $compositeKey = "$($entry.Path)\$($entry.ValueName)"
        $typeMap[$compositeKey] = $entry.Type
    }

    # ------------------------------------------------------------------
    # Restore each registry entry
    # ------------------------------------------------------------------
    Write-Host '[Restore] Writing registry values...' -ForegroundColor Cyan

    # ConvertFrom-Json turns the Registry object into a PSCustomObject.
    # Iterate its NoteProperties to get each composite key.
    $registryObject = $backup.Registry
    $registryProperties = $registryObject | Get-Member -MemberType NoteProperty

    foreach ($prop in $registryProperties) {
        $compositeKey = $prop.Name
        $storedValue = $registryObject.$compositeKey

        # Determine the registry path and value name from the composite key.
        # The composite key format is "HKCU:\...\ParentKey\ValueName".
        # The manifest tells us the split point, so use the lookup first.
        $keyType = 'String'
        if ($typeMap.ContainsKey($compositeKey)) {
            $keyType = $typeMap[$compositeKey]
        }
        else {
            $null = $warnings.Add("Unknown key in backup (not in manifest): $compositeKey")
            Write-Host "  [??] $compositeKey (unknown, skipping)" -ForegroundColor Yellow
            continue
        }

        # Split the composite key back into Path and ValueName. We find
        # the matching manifest entry rather than doing fragile string
        # splitting on a path that may contain backslashes.
        $matchingEntry = $manifest | Where-Object {
            "$($_.Path)\$($_.ValueName)" -eq $compositeKey
        } | Select-Object -First 1

        if ($null -eq $matchingEntry) {
            $null = $warnings.Add("Cannot split composite key: $compositeKey")
            continue
        }

        $regPath = $matchingEntry.Path
        $regValueName = $matchingEntry.ValueName

        if ($PSCmdlet.ShouldProcess("$regPath -> $regValueName", 'Restore registry value')) {
            $writeResult = Write-RegistryValue `
                -Path $regPath `
                -ValueName $regValueName `
                -Value $storedValue `
                -Type $keyType

            if ($writeResult.Success) {
                $restoredKeys++
                switch ($writeResult.Action) {
                    'Set'    { Write-Host "  [OK] $compositeKey (restored)" -ForegroundColor Green }
                    'Remove' { Write-Host "  [OK] $compositeKey (removed)" -ForegroundColor Green }
                    'Skip'   { Write-Host "  [--] $compositeKey (already absent)" -ForegroundColor DarkGray }
                }
            }
            else {
                $null = $warnings.Add("Failed to restore $compositeKey : $($writeResult.Action)")
                Write-Host "  [!!] $compositeKey ($($writeResult.Action))" -ForegroundColor Red
            }
        }
        else {
            $restoredKeys++
            Write-Host "  [WhatIf] Would restore $compositeKey" -ForegroundColor Yellow
        }
    }

    # ------------------------------------------------------------------
    # Report wallpaper and cursor scheme status
    # ------------------------------------------------------------------
    $wallpaperValue = $backup.Wallpaper
    $cursorValue = $backup.CursorScheme

    Write-Host "  Wallpaper path : $wallpaperValue (written via registry; caller must invoke SystemParametersInfo to refresh)" -ForegroundColor Cyan
    Write-Host "  Cursor scheme  : $cursorValue" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Return structured result
    # ------------------------------------------------------------------
    $success = ($warnings.Count -eq 0)

    if ($warnings.Count -gt 0) {
        Write-Host "[Restore] Completed with $($warnings.Count) warning(s)" -ForegroundColor Yellow
    }
    else {
        Write-Host '[Restore] Completed successfully' -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Success      = $success
        RestoredKeys = $restoredKeys
        Warnings     = $warnings.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Restore-OriginalSettings'
)
