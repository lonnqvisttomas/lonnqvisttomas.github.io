#Requires -Version 5.1

<#
.SYNOPSIS
    Reverts the macOS theme and restores original Windows 11 settings.

.DESCRIPTION
    Reads the backup snapshot created by Install-MacTheme.ps1 and restores all
    original Windows settings — taskbar, visual style, wallpaper, cursors, and
    Start menu configuration. After a successful restore the backup directory
    at %APPDATA%\WinToMac is removed.

    Requires that Install-MacTheme.ps1 was previously run so that a backup
    exists. If no backup is found, the script exits with a clear error.

    Supports -WhatIf to preview all operations without making changes.

.PARAMETER NoRestart
    Suppress the Explorer restart prompt. Changes will not take full effect
    until Explorer is manually restarted or the system is rebooted.

.EXAMPLE
    .\Uninstall-MacTheme.ps1
    Restores all original settings and prompts to restart Explorer.

.EXAMPLE
    .\Uninstall-MacTheme.ps1 -NoRestart
    Restores all original settings without restarting Explorer.

.EXAMPLE
    .\Uninstall-MacTheme.ps1 -WhatIf
    Previews all restore operations without executing them.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
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
Write-Host '  WinToMac — macOS Theme Uninstaller for Windows 11'  -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

$startTime = Get-Date

# ---------------------------------------------------------------------------
# Verify backup exists
# ---------------------------------------------------------------------------

$backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
$backupPath = Join-Path -Path $backupDir -ChildPath 'backup.json'

if (-not (Test-Path -Path $backupPath -PathType Leaf)) {
    Write-Host '[Backup] No backup found at:' -ForegroundColor Red
    Write-Host "         $backupPath" -ForegroundColor Red
    Write-Host '' -ForegroundColor Red
    Write-Host '         Install-MacTheme.ps1 must be run before uninstalling.' -ForegroundColor Red
    Write-Host '         Cannot restore original settings without a backup.' -ForegroundColor Red
    throw "Backup not found at '$backupPath'. Run Install-MacTheme.ps1 first."
}

Write-Host "[Backup] Backup found at: $backupPath" -ForegroundColor Green

# ---------------------------------------------------------------------------
# Restore original settings
# ---------------------------------------------------------------------------

$restoreResult = $null

try {
    Write-Host ''
    Write-Host '[Restore] Restoring original Windows settings...' -ForegroundColor Cyan
    $restoreResult = Restore-OriginalSettings -WhatIf:$WhatIfPreference

    if ($restoreResult.Success) {
        Write-Host '[Restore] All settings restored successfully.' -ForegroundColor Green
    }
    else {
        Write-Host '[Restore] Restore completed with errors.' -ForegroundColor Yellow
    }
}
catch {
    Write-Host "[Restore] Failed to restore settings: $_" -ForegroundColor Red
    $restoreResult = [PSCustomObject]@{
        Success = $false
        Error   = $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Explorer restart
# ---------------------------------------------------------------------------

Invoke-ExplorerRestart -NoRestart:$NoRestart

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------

$cleanedUp = $false

if ($null -ne $restoreResult -and $restoreResult.Success) {
    if ($PSCmdlet.ShouldProcess($backupDir, 'Remove backup directory')) {
        try {
            Write-Host ''
            Write-Host "[Cleanup] Removing backup directory: $backupDir" -ForegroundColor Cyan
            Remove-Item -Path $backupDir -Recurse -Force
            $cleanedUp = $true
            Write-Host '[Cleanup] Backup directory removed.' -ForegroundColor Green
        }
        catch {
            Write-Host "[Cleanup] Failed to remove backup directory: $_" -ForegroundColor Yellow
            # Non-fatal — the uninstall still succeeded
        }
    }

    # Also clean up cursor files deployed to LOCALAPPDATA
    $localAppDataDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WinToMac'
    if (Test-Path -Path $localAppDataDir) {
        if ($PSCmdlet.ShouldProcess($localAppDataDir, 'Remove cursor deployment directory')) {
            try {
                Write-Host "[Cleanup] Removing cursor directory: $localAppDataDir" -ForegroundColor Cyan
                Remove-Item -Path $localAppDataDir -Recurse -Force
                Write-Host '[Cleanup] Cursor directory removed.' -ForegroundColor Green
            }
            catch {
                Write-Host "[Cleanup] Failed to remove cursor directory: $_" -ForegroundColor Yellow
            }
        }
    }
}
else {
    Write-Host ''
    Write-Host '[Cleanup] Skipping cleanup — restore did not fully succeed. Backup preserved for retry.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  Uninstall Summary'                                   -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "  Start Time : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  End Time   : $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  Duration   : $($duration.ToString())"
Write-Host ''

if ($null -ne $restoreResult -and $restoreResult.Success) {
    Write-Host '  Restore    : SUCCESS' -ForegroundColor Green
}
else {
    Write-Host '  Restore    : FAILED' -ForegroundColor Red
}

if ($cleanedUp) {
    Write-Host '  Cleanup    : DONE' -ForegroundColor Green
}
else {
    Write-Host '  Cleanup    : SKIPPED' -ForegroundColor Yellow
}

Write-Host ''
if ($null -ne $restoreResult -and $restoreResult.Success) {
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
    OverallSuccess = ($null -ne $restoreResult -and $restoreResult.Success)
    RestoreResult  = $restoreResult
    StartTime      = $startTime
    EndTime        = $endTime
    Duration       = $duration
    CleanedUp      = $cleanedUp
}
