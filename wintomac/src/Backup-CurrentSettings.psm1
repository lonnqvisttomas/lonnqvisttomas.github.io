# Backup-CurrentSettings.psm1 — Snapshot current Windows settings before
# applying the macOS theme so they can be restored later.
#
# Uses a static key manifest (Design Decision #1) — a hardcoded list of
# every registry path/value the WinToMac module touches. Before any
# modification, each value is read (or recorded as $null if absent).
# The snapshot is written as JSON to $env:APPDATA\WinToMac\backup.json.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Get-BackupKeyManifest — Return the full static list of registry keys
# ---------------------------------------------------------------------------

function Get-BackupKeyManifest {
    <#
    .SYNOPSIS
        Returns the static key manifest used by backup and restore operations.

    .DESCRIPTION
        Provides the complete list of registry paths and value names that the
        WinToMac module modifies. Each entry includes the registry path, value
        name, and the expected value type so that binary values can be
        serialized and deserialized correctly.

        This function is shared between Backup-CurrentSettings and
        Restore-OriginalSettings.

    .OUTPUTS
        System.Collections.Hashtable[] — Array of hashtables, each with keys:
        Path (string), ValueName (string), Type (string: 'DWord', 'String',
        'Binary', 'ExpandString').

    .EXAMPLE
        $manifest = Get-BackupKeyManifest
        $manifest | ForEach-Object { "$($_.Path) -> $($_.ValueName) [$($_.Type)]" }
    #>
    [CmdletBinding()]
    param()

    $explorerAdvanced = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $search           = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
    $stuckRects       = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $personalize      = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $accent           = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    $startMenu        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start'
    $desktop          = 'HKCU:\Control Panel\Desktop'
    $cursors          = 'HKCU:\Control Panel\Cursors'
    $hklmCursorSchemes = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cursors\Schemes'

    return @(
        # ---- Taskbar keys ------------------------------------------------
        @{ Path = $explorerAdvanced; ValueName = 'TaskbarAl';          Type = 'DWord' }
        @{ Path = $explorerAdvanced; ValueName = 'TaskbarSi';          Type = 'DWord' }
        @{ Path = $explorerAdvanced; ValueName = 'ShowTaskViewButton';  Type = 'DWord' }
        @{ Path = $explorerAdvanced; ValueName = 'TaskbarDa';          Type = 'DWord' }
        @{ Path = $search;           ValueName = 'SearchboxTaskbarMode'; Type = 'DWord' }
        @{ Path = $stuckRects;       ValueName = 'Settings';           Type = 'Binary' }

        # ---- Visual style keys -------------------------------------------
        @{ Path = $personalize; ValueName = 'AppsUseLightTheme';    Type = 'DWord' }
        @{ Path = $personalize; ValueName = 'SystemUsesLightTheme'; Type = 'DWord' }
        @{ Path = $personalize; ValueName = 'EnableTransparency';   Type = 'DWord' }
        @{ Path = $personalize; ValueName = 'ColorPrevalence';      Type = 'DWord' }
        @{ Path = $accent;      ValueName = 'AccentColorMenu';      Type = 'DWord' }
        @{ Path = $accent;      ValueName = 'AccentPalette';        Type = 'Binary' }

        # ---- Start menu keys ---------------------------------------------
        @{ Path = $explorerAdvanced; ValueName = 'Start_Layout';    Type = 'DWord' }
        @{ Path = $startMenu;        ValueName = 'VisiblePlaces';   Type = 'Binary' }

        # ---- Wallpaper keys ----------------------------------------------
        @{ Path = $desktop; ValueName = 'Wallpaper';      Type = 'String' }
        @{ Path = $desktop; ValueName = 'WallpaperStyle';  Type = 'String' }
        @{ Path = $desktop; ValueName = 'TileWallpaper';   Type = 'String' }

        # ---- Cursor keys -------------------------------------------------
        @{ Path = $cursors; ValueName = '(Default)';    Type = 'String' }
        @{ Path = $cursors; ValueName = 'Arrow';        Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'Help';         Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'AppStarting';  Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'Wait';         Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'Crosshair';    Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'IBeam';        Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'NWPen';        Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'No';           Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'SizeNS';       Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'SizeWE';       Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'SizeNWSE';     Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'SizeNESW';     Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'SizeAll';      Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'UpArrow';      Type = 'ExpandString' }
        @{ Path = $cursors; ValueName = 'Hand';         Type = 'ExpandString' }

        # ---- HKLM cursor scheme registration -----------------------------
        @{ Path = $hklmCursorSchemes; ValueName = 'WinToMac'; Type = 'String' }
    )
}

# ---------------------------------------------------------------------------
# Read-RegistryValue — Safely read a single registry value
# ---------------------------------------------------------------------------

function Read-RegistryValue {
    <#
    .SYNOPSIS
        Reads a single registry value, returning $null when the key or value
        does not exist.

    .PARAMETER Path
        The registry key path (e.g., HKCU:\...).

    .PARAMETER ValueName
        The name of the value to read.

    .OUTPUTS
        The raw value, or $null if the key/value is absent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$ValueName
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            return $null
        }

        # The (Default) value is accessed via the empty-string name in
        # Get-ItemProperty, but it shows up as '(default)' in the object.
        if ($ValueName -eq '(Default)') {
            $item = Get-ItemProperty -Path $Path -Name '(Default)' -ErrorAction Stop
            return $item.'(Default)'
        }

        $item = Get-ItemProperty -Path $Path -Name $ValueName -ErrorAction Stop
        return $item.$ValueName
    }
    catch {
        # Value does not exist — this is expected for keys the module has
        # not yet created.
        return $null
    }
}

# ---------------------------------------------------------------------------
# Backup-CurrentSettings — Main exported function
# ---------------------------------------------------------------------------

function Backup-CurrentSettings {
    <#
    .SYNOPSIS
        Captures all current Windows settings that the WinToMac module
        will modify and writes them to a JSON backup file.

    .DESCRIPTION
        Iterates every entry in the static key manifest (returned by
        Get-BackupKeyManifest), reads the current value from the registry,
        and serializes the snapshot to JSON at
        $env:APPDATA\WinToMac\backup.json.

        Binary values (e.g., StuckRects3 Settings, AccentPalette) are stored
        as Base64-encoded strings so the JSON remains text-safe.

        Values that do not exist in the registry are recorded as $null so
        that Restore-OriginalSettings can remove them on revert.

        Supports -WhatIf: in WhatIf mode all values are read and reported
        but the JSON file is not written to disk.

    .EXAMPLE
        $result = Backup-CurrentSettings
        if ($result.Success) { Write-Host "Backup saved to $($result.BackupPath)" }

    .EXAMPLE
        Backup-CurrentSettings -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success (bool), BackupPath (string),
        KeyCount (int), Warnings (string[]).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $warnings = [System.Collections.ArrayList]::new()
    $backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
    $backupPath = Join-Path -Path $backupDir -ChildPath 'backup.json'

    Write-Host '[Backup] Reading current settings...' -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Build the registry snapshot
    # ------------------------------------------------------------------
    $manifest = Get-BackupKeyManifest
    $registrySnapshot = @{}

    foreach ($entry in $manifest) {
        $compositeKey = "$($entry.Path)\$($entry.ValueName)"

        $rawValue = Read-RegistryValue -Path $entry.Path -ValueName $entry.ValueName

        if ($null -eq $rawValue) {
            $registrySnapshot[$compositeKey] = $null
            Write-Host "  [--] $compositeKey (not present)" -ForegroundColor DarkGray
        }
        elseif ($entry.Type -eq 'Binary') {
            # Encode binary (byte[]) as Base64 for JSON safety.
            try {
                $base64 = [Convert]::ToBase64String([byte[]]$rawValue)
                $registrySnapshot[$compositeKey] = @{
                    _type = 'Binary'
                    Value = $base64
                }
                Write-Host "  [OK] $compositeKey (binary, $($rawValue.Length) bytes)" -ForegroundColor Green
            }
            catch {
                $null = $warnings.Add("Failed to encode binary value for $compositeKey : $($_.Exception.Message)")
                $registrySnapshot[$compositeKey] = $null
                Write-Host "  [!!] $compositeKey (binary encode failed)" -ForegroundColor Yellow
            }
        }
        else {
            $registrySnapshot[$compositeKey] = $rawValue
            Write-Host "  [OK] $compositeKey = $rawValue" -ForegroundColor Green
        }
    }

    # ------------------------------------------------------------------
    # Capture wallpaper path and cursor scheme name
    # ------------------------------------------------------------------
    $wallpaperPath = Read-RegistryValue `
        -Path 'HKCU:\Control Panel\Desktop' `
        -ValueName 'Wallpaper'

    $cursorScheme = Read-RegistryValue `
        -Path 'HKCU:\Control Panel\Cursors' `
        -ValueName '(Default)'

    Write-Host "  Wallpaper : $wallpaperPath" -ForegroundColor Cyan
    Write-Host "  Cursor    : $cursorScheme" -ForegroundColor Cyan

    # ------------------------------------------------------------------
    # Assemble the backup object
    # ------------------------------------------------------------------
    $backup = [ordered]@{
        Version      = '1.0'
        Timestamp    = (Get-Date).ToUniversalTime().ToString('o')
        Registry     = $registrySnapshot
        Wallpaper    = $wallpaperPath
        CursorScheme = $cursorScheme
    }

    # ------------------------------------------------------------------
    # Write to disk (respects -WhatIf)
    # ------------------------------------------------------------------
    if ($PSCmdlet.ShouldProcess($backupPath, 'Write backup JSON file')) {
        try {
            if (-not (Test-Path -Path $backupDir -PathType Container)) {
                $null = New-Item -Path $backupDir -ItemType Directory -Force
                Write-Host "  Created directory: $backupDir" -ForegroundColor Cyan
            }

            $jsonContent = $backup | ConvertTo-Json -Depth 10
            [System.IO.File]::WriteAllText($backupPath, $jsonContent, [System.Text.Encoding]::UTF8)
            Write-Host "[Backup] Saved to $backupPath" -ForegroundColor Green
        }
        catch {
            $errorMsg = "Failed to write backup file: $($_.Exception.Message)"
            $null = $warnings.Add($errorMsg)
            Write-Host "[Backup] $errorMsg" -ForegroundColor Red

            return [PSCustomObject]@{
                Success    = $false
                BackupPath = $backupPath
                KeyCount   = $registrySnapshot.Count
                Warnings   = $warnings.ToArray()
            }
        }
    }
    else {
        Write-Host "[Backup] WhatIf: Would write backup to $backupPath ($($registrySnapshot.Count) keys)" -ForegroundColor Yellow
    }

    # ------------------------------------------------------------------
    # Return structured result
    # ------------------------------------------------------------------
    if ($warnings.Count -gt 0) {
        Write-Host "[Backup] Completed with $($warnings.Count) warning(s)" -ForegroundColor Yellow
    }
    else {
        Write-Host '[Backup] Completed successfully' -ForegroundColor Green
    }

    return [PSCustomObject]@{
        Success    = $true
        BackupPath = $backupPath
        KeyCount   = $registrySnapshot.Count
        Warnings   = $warnings.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Get-BackupKeyManifest',
    'Backup-CurrentSettings'
)
