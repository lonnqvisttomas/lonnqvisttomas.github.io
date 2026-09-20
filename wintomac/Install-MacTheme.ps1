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
            $config.PSObject.Properties['SkipDock'] -and $config.SkipDock -eq $true) {
            $SkipDock = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipCursors') -and
            $config.PSObject.Properties['SkipCursors'] -and $config.SkipCursors -eq $true) {
            $SkipCursors = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipWallpaper') -and
            $config.PSObject.Properties['SkipWallpaper'] -and $config.SkipWallpaper -eq $true) {
            $SkipWallpaper = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipStartMenu') -and
            $config.PSObject.Properties['SkipStartMenu'] -and $config.SkipStartMenu -eq $true) {
            $SkipStartMenu = [switch]$true
        }
        if (-not $PSBoundParameters.ContainsKey('SkipVisualStyle') -and
            $config.PSObject.Properties['SkipVisualStyle'] -and $config.SkipVisualStyle -eq $true) {
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

$themeSteps = @(
    [PSCustomObject]@{ Name = 'Dock';        Skip = [bool]$SkipDock;        Action = { Set-TaskbarConfig -WhatIf:$WhatIfPreference } }
    [PSCustomObject]@{ Name = 'VisualStyle'; Skip = [bool]$SkipVisualStyle; Action = { Set-VisualStyle -WhatIf:$WhatIfPreference } }
    [PSCustomObject]@{ Name = 'Wallpaper';   Skip = [bool]$SkipWallpaper;   Action = { Set-Wallpaper -WhatIf:$WhatIfPreference } }
    [PSCustomObject]@{ Name = 'Cursors';     Skip = [bool]$SkipCursors;     Action = { Set-CursorScheme -WhatIf:$WhatIfPreference } }
    [PSCustomObject]@{ Name = 'StartMenu';   Skip = [bool]$SkipStartMenu;   Action = { Set-StartMenuConfig -WhatIf:$WhatIfPreference } }
)

foreach ($step in $themeSteps) {
    if (-not $step.Skip) {
        try {
            Write-Host ''
            Write-Host "[$($step.Name)] Applying $($step.Name) configuration..." -ForegroundColor Cyan
            $stepResult = & $step.Action
            $steps.Add([PSCustomObject]@{ Name = $step.Name; Success = $true; Result = $stepResult }) | Out-Null
            Write-Host "[$($step.Name)] $($step.Name) applied successfully." -ForegroundColor Green
        }
        catch {
            Write-Host "[$($step.Name)] Failed: $_" -ForegroundColor Red
            $steps.Add([PSCustomObject]@{ Name = $step.Name; Success = $false; Error = $_.Exception.Message }) | Out-Null
            $overallSuccess = $false
        }
    }
    else {
        Write-Host ''
        Write-Host "[$($step.Name)] Skipped (Skip$($step.Name) specified)." -ForegroundColor Yellow
        $steps.Add([PSCustomObject]@{ Name = $step.Name; Success = $true; Skipped = $true }) | Out-Null
    }
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
