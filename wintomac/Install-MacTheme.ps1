#Requires -Version 5.1

<#
.SYNOPSIS
    Transforms Windows 11 to look like macOS by applying a comprehensive theme.

.DESCRIPTION
    Orchestrates the full macOS theme installation across multiple components:
    taskbar/dock, visual style, wallpaper, cursors, and Start menu. Each
    component can be individually skipped via switch parameters or a JSON
    configuration file. A backup of the current Windows settings is created
    before the first install and preserved across subsequent runs so that
    Uninstall-MacTheme.ps1 can always revert to the original state.

    Supports -WhatIf to preview all operations without making changes.

.PARAMETER SkipDock
    Skip the taskbar-to-dock transformation step.

.PARAMETER SkipCursors
    Skip the macOS cursor scheme installation step.

.PARAMETER SkipWallpaper
    Skip the macOS wallpaper application step.

.PARAMETER SkipStartMenu
    Skip the Start menu reconfiguration step.

.PARAMETER SkipVisualStyle
    Skip the visual style (title bars, window chrome) application step.

.PARAMETER ConfigPath
    Path to a JSON configuration file. The file may contain boolean properties
    matching the skip switches (e.g. "SkipDock": true) to control which
    components are applied. Switch parameters supplied on the command line
    take precedence over config file values.

.PARAMETER NoRestart
    Suppress the Explorer restart prompt. Changes will not take full effect
    until Explorer is manually restarted or the system is rebooted.

.EXAMPLE
    .\Install-MacTheme.ps1
    Applies the full macOS theme with an interactive Explorer restart prompt.

.EXAMPLE
    .\Install-MacTheme.ps1 -SkipDock -SkipCursors
    Applies the theme but skips the dock and cursor components.

.EXAMPLE
    .\Install-MacTheme.ps1 -ConfigPath .\config.json -NoRestart
    Applies the theme using settings from the config file and skips the
    Explorer restart.

.EXAMPLE
    .\Install-MacTheme.ps1 -WhatIf
    Previews all operations without executing them.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [switch]$SkipDock,
    [switch]$SkipCursors,
    [switch]$SkipWallpaper,
    [switch]$SkipStartMenu,
    [switch]$SkipVisualStyle,
    [string]$ConfigPath,
    [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Import the WinToMac module
# ---------------------------------------------------------------------------

try {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'WinToMac.psd1'
    Import-Module -Name $manifestPath -Force -ErrorAction Stop
    Write-Host '[WinToMac] Module loaded successfully.' -ForegroundColor Cyan
}
catch {
    Write-Host "[WinToMac] Failed to load module: $_" -ForegroundColor Red
    throw
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  WinToMac — macOS Theme Installer for Windows 11'    -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

$startTime = Get-Date

# ---------------------------------------------------------------------------
# Load JSON config and merge skip switches
# ---------------------------------------------------------------------------

if ($ConfigPath) {
    if (-not (Test-Path -Path $ConfigPath -PathType Leaf)) {
        Write-Host "[Config] Configuration file not found: $ConfigPath" -ForegroundColor Red
        throw "Configuration file not found: $ConfigPath"
    }

    try {
        Write-Host "[Config] Loading configuration from: $ConfigPath" -ForegroundColor Cyan
        $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

        # Config values apply only when the corresponding switch was NOT
        # explicitly supplied on the command line.
        if (-not $PSBoundParameters.ContainsKey('SkipDock') -and
            $null -ne $config.SkipDock -and $config.SkipDock -eq $true) {
            $SkipDock = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipCursors') -and
            $null -ne $config.SkipCursors -and $config.SkipCursors -eq $true) {
            $SkipCursors = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipWallpaper') -and
            $null -ne $config.SkipWallpaper -and $config.SkipWallpaper -eq $true) {
            $SkipWallpaper = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipStartMenu') -and
            $null -ne $config.SkipStartMenu -and $config.SkipStartMenu -eq $true) {
            $SkipStartMenu = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipVisualStyle') -and
            $null -ne $config.SkipVisualStyle -and $config.SkipVisualStyle -eq $true) {
            $SkipVisualStyle = [switch]$true
        }

        Write-Host '[Config] Configuration loaded successfully.' -ForegroundColor Green
    }
    catch [System.Management.Automation.ItemNotFoundException] {
        throw
    }
    catch {
        Write-Host "[Config] Failed to parse configuration file: $_" -ForegroundColor Red
        throw
    }
}

# ---------------------------------------------------------------------------
# Tracking variables
# ---------------------------------------------------------------------------

$overallSuccess = $true
$backupResult = $null
$steps = [System.Collections.ArrayList]::new()

# ---------------------------------------------------------------------------
# Backup phase
# ---------------------------------------------------------------------------

$backupPath = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'

try {
    Write-Host '[Backup] Checking for existing backup...' -ForegroundColor Cyan

    if (Test-Path -Path $backupPath -PathType Leaf) {
        Write-Host '[Backup] Existing backup found — preserving original settings.' -ForegroundColor Yellow
        $backupResult = [PSCustomObject]@{
            Success = $true
            Skipped = $true
            Message = 'Existing backup preserved'
        }
    }
    else {
        Write-Host '[Backup] No existing backup found — creating backup of current settings...' -ForegroundColor Cyan
        $backupResult = Backup-CurrentSettings -WhatIf:$WhatIfPreference

        if ($backupResult.Success) {
            Write-Host '[Backup] Backup created successfully.' -ForegroundColor Green
        }
        else {
            Write-Host '[Backup] Backup completed with warnings.' -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "[Backup] Failed to create backup: $_" -ForegroundColor Red
    $backupResult = [PSCustomObject]@{
        Success = $false
        Skipped = $false
        Message = $_.Exception.Message
    }
    $overallSuccess = $false
}

# ---------------------------------------------------------------------------
# Apply phases
# ---------------------------------------------------------------------------

# --- Dock / Taskbar ---
if (-not $SkipDock) {
    try {
        Write-Host ''
        Write-Host '[Dock] Configuring taskbar as macOS-style dock...' -ForegroundColor Cyan
        $dockResult = Set-TaskbarConfig -WhatIf:$WhatIfPreference
        $steps.Add([PSCustomObject]@{ Name = 'Dock'; Success = $true; Result = $dockResult }) | Out-Null
        Write-Host '[Dock] Dock configuration applied successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "[Dock] Failed to configure dock: $_" -ForegroundColor Red
        $steps.Add([PSCustomObject]@{ Name = 'Dock'; Success = $false; Error = $_.Exception.Message }) | Out-Null
        $overallSuccess = $false
    }
}
else {
    Write-Host ''
    Write-Host '[Dock] Skipped (SkipDock specified).' -ForegroundColor Yellow
    $steps.Add([PSCustomObject]@{ Name = 'Dock'; Success = $true; Skipped = $true }) | Out-Null
}

# --- Visual Style ---
if (-not $SkipVisualStyle) {
    try {
        Write-Host ''
        Write-Host '[VisualStyle] Applying macOS visual style...' -ForegroundColor Cyan
        $vsResult = Set-VisualStyle -WhatIf:$WhatIfPreference
        $steps.Add([PSCustomObject]@{ Name = 'VisualStyle'; Success = $true; Result = $vsResult }) | Out-Null
        Write-Host '[VisualStyle] Visual style applied successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "[VisualStyle] Failed to apply visual style: $_" -ForegroundColor Red
        $steps.Add([PSCustomObject]@{ Name = 'VisualStyle'; Success = $false; Error = $_.Exception.Message }) | Out-Null
        $overallSuccess = $false
    }
}
else {
    Write-Host ''
    Write-Host '[VisualStyle] Skipped (SkipVisualStyle specified).' -ForegroundColor Yellow
    $steps.Add([PSCustomObject]@{ Name = 'VisualStyle'; Success = $true; Skipped = $true }) | Out-Null
}

# --- Wallpaper ---
if (-not $SkipWallpaper) {
    try {
        Write-Host ''
        Write-Host '[Wallpaper] Setting macOS wallpaper...' -ForegroundColor Cyan
        $wpResult = Set-Wallpaper -WhatIf:$WhatIfPreference
        $steps.Add([PSCustomObject]@{ Name = 'Wallpaper'; Success = $true; Result = $wpResult }) | Out-Null
        Write-Host '[Wallpaper] Wallpaper applied successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "[Wallpaper] Failed to set wallpaper: $_" -ForegroundColor Red
        $steps.Add([PSCustomObject]@{ Name = 'Wallpaper'; Success = $false; Error = $_.Exception.Message }) | Out-Null
        $overallSuccess = $false
    }
}
else {
    Write-Host ''
    Write-Host '[Wallpaper] Skipped (SkipWallpaper specified).' -ForegroundColor Yellow
    $steps.Add([PSCustomObject]@{ Name = 'Wallpaper'; Success = $true; Skipped = $true }) | Out-Null
}

# --- Cursors ---
if (-not $SkipCursors) {
    try {
        Write-Host ''
        Write-Host '[Cursors] Installing macOS cursor scheme...' -ForegroundColor Cyan
        $cursorResult = Set-CursorScheme -WhatIf:$WhatIfPreference
        $steps.Add([PSCustomObject]@{ Name = 'Cursors'; Success = $true; Result = $cursorResult }) | Out-Null
        Write-Host '[Cursors] Cursor scheme installed successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "[Cursors] Failed to install cursor scheme: $_" -ForegroundColor Red
        $steps.Add([PSCustomObject]@{ Name = 'Cursors'; Success = $false; Error = $_.Exception.Message }) | Out-Null
        $overallSuccess = $false
    }
}
else {
    Write-Host ''
    Write-Host '[Cursors] Skipped (SkipCursors specified).' -ForegroundColor Yellow
    $steps.Add([PSCustomObject]@{ Name = 'Cursors'; Success = $true; Skipped = $true }) | Out-Null
}

# --- Start Menu ---
if (-not $SkipStartMenu) {
    try {
        Write-Host ''
        Write-Host '[StartMenu] Reconfiguring Start menu...' -ForegroundColor Cyan
        $smResult = Set-StartMenuConfig -WhatIf:$WhatIfPreference
        $steps.Add([PSCustomObject]@{ Name = 'StartMenu'; Success = $true; Result = $smResult }) | Out-Null
        Write-Host '[StartMenu] Start menu configured successfully.' -ForegroundColor Green
    }
    catch {
        Write-Host "[StartMenu] Failed to configure Start menu: $_" -ForegroundColor Red
        $steps.Add([PSCustomObject]@{ Name = 'StartMenu'; Success = $false; Error = $_.Exception.Message }) | Out-Null
        $overallSuccess = $false
    }
}
else {
    Write-Host ''
    Write-Host '[StartMenu] Skipped (SkipStartMenu specified).' -ForegroundColor Yellow
    $steps.Add([PSCustomObject]@{ Name = 'StartMenu'; Success = $true; Skipped = $true }) | Out-Null
}

# ---------------------------------------------------------------------------
# Explorer restart
# ---------------------------------------------------------------------------

Invoke-ExplorerRestart -NoRestart:$NoRestart

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  Installation Summary'                                -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "  Start Time : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  End Time   : $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  Duration   : $($duration.ToString())"
Write-Host ''

# Backup status
if ($null -ne $backupResult) {
    if ($backupResult.Success) {
        Write-Host '  Backup     : OK' -ForegroundColor Green
    }
    else {
        Write-Host '  Backup     : FAILED' -ForegroundColor Red
    }
}

# Step statuses
foreach ($step in $steps) {
    $label = $step.Name.PadRight(12)
    if ($step.PSObject.Properties['Skipped'] -and $step.Skipped) {
        Write-Host "  $label : SKIPPED" -ForegroundColor Yellow
    }
    elseif ($step.Success) {
        Write-Host "  $label : PASS" -ForegroundColor Green
    }
    else {
        Write-Host "  $label : FAIL" -ForegroundColor Red
    }
}

Write-Host ''
if ($overallSuccess) {
    Write-Host '  Overall    : SUCCESS' -ForegroundColor Green
}
else {
    Write-Host '  Overall    : COMPLETED WITH ERRORS' -ForegroundColor Red
}

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Return structured result
# ---------------------------------------------------------------------------

[PSCustomObject]@{
    OverallSuccess = $overallSuccess
    BackupResult   = $backupResult
    Steps          = $steps.ToArray()
    StartTime      = $startTime
    EndTime        = $endTime
    Duration       = $duration
}
