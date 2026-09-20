# Set-TaskbarConfig.psm1 — Taskbar appearance and behaviour configuration
#
# Auto-hides the taskbar, centers icons, sets small taskbar size, and removes
# the search box, Task View button, and widgets via registry writes.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Set-RegistryValue — Shared helper (dot-sourced)
# ---------------------------------------------------------------------------

. (Join-Path -Path $PSScriptRoot -ChildPath 'RegistryHelpers.ps1')

# ---------------------------------------------------------------------------
# Set-TaskbarConfig — Main exported function
# ---------------------------------------------------------------------------

function Set-TaskbarConfig {
    <#
    .SYNOPSIS
        Configures the Windows 11 taskbar to resemble the macOS Dock.

    .DESCRIPTION
        Applies several registry tweaks to the current user hive:
          - Centers taskbar icons (TaskbarAl = 1)
          - Sets small taskbar size (TaskbarSi = 0)
          - Hides the Task View button (ShowTaskViewButton = 0)
          - Disables Widgets (TaskbarDa = 0)
          - Hides the search box (SearchboxTaskbarMode = 0)
          - Enables taskbar auto-hide via the StuckRects3 binary blob

        Returns a structured result object with Success, Changes, and Warnings
        properties.

    .EXAMPLE
        $result = Set-TaskbarConfig
        if ($result.Success) { Write-Host 'Taskbar configured.' }

    .EXAMPLE
        Set-TaskbarConfig -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success (bool), Changes (string[]),
        Warnings (string[]).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $changes  = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    Write-Host "`nConfiguring taskbar settings..." -ForegroundColor Cyan

    $advancedPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $searchPath   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
    $stuckPath    = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'

    # ------------------------------------------------------------------
    # 1. Center-aligned taskbar icons
    # ------------------------------------------------------------------
    Write-Host "`n  [1/6] Setting taskbar alignment to center..." -ForegroundColor Cyan
    Set-RegistryValue -Path $advancedPath -Name 'TaskbarAl' -Value 1
    $null = $changes.Add('Taskbar alignment set to center (TaskbarAl = 1)')

    # ------------------------------------------------------------------
    # 2. Small taskbar size
    # ------------------------------------------------------------------
    Write-Host "  [2/6] Setting small taskbar size..." -ForegroundColor Cyan
    Set-RegistryValue -Path $advancedPath -Name 'TaskbarSi' -Value 0
    $null = $changes.Add('Taskbar size set to small (TaskbarSi = 0)')

    # ------------------------------------------------------------------
    # 3. Hide Task View button
    # ------------------------------------------------------------------
    Write-Host "  [3/6] Hiding Task View button..." -ForegroundColor Cyan
    Set-RegistryValue -Path $advancedPath -Name 'ShowTaskViewButton' -Value 0
    $null = $changes.Add('Task View button hidden (ShowTaskViewButton = 0)')

    # ------------------------------------------------------------------
    # 4. Disable Widgets
    # ------------------------------------------------------------------
    Write-Host "  [4/6] Disabling Widgets..." -ForegroundColor Cyan
    Set-RegistryValue -Path $advancedPath -Name 'TaskbarDa' -Value 0
    $null = $changes.Add('Widgets disabled (TaskbarDa = 0)')

    # ------------------------------------------------------------------
    # 5. Hide Search box
    # ------------------------------------------------------------------
    Write-Host "  [5/6] Hiding search box..." -ForegroundColor Cyan
    Set-RegistryValue -Path $searchPath -Name 'SearchboxTaskbarMode' -Value 0
    $null = $changes.Add('Search box hidden (SearchboxTaskbarMode = 0)')

    # ------------------------------------------------------------------
    # 6. Auto-hide taskbar via StuckRects3 binary blob
    # ------------------------------------------------------------------
    Write-Host "  [6/6] Enabling taskbar auto-hide..." -ForegroundColor Cyan

    if (Test-Path -Path $stuckPath) {
        try {
            $settings = (Get-ItemProperty -Path $stuckPath -Name 'Settings').Settings

            if ($null -ne $settings -and $settings.Length -gt 8) {
                # Set the auto-hide flag: byte 8, bits 0 and 1
                $settings[8] = $settings[8] -bor 0x03

                if ($PSCmdlet.ShouldProcess("$stuckPath\Settings", 'Enable auto-hide bit in binary blob')) {
                    Set-ItemProperty -Path $stuckPath -Name 'Settings' -Value $settings -Type Binary
                    Write-Host "  Auto-hide flag enabled in StuckRects3" -ForegroundColor Green
                    $null = $changes.Add('Taskbar auto-hide enabled (StuckRects3 byte[8] |= 0x03)')
                }
            }
            else {
                $msg = 'StuckRects3\Settings binary value is missing or too short; skipping auto-hide'
                Write-Warning $msg
                $null = $warnings.Add($msg)
            }
        }
        catch {
            $msg = "Failed to modify StuckRects3: $($_.Exception.Message)"
            Write-Warning $msg
            $null = $warnings.Add($msg)
        }
    }
    else {
        $msg = 'StuckRects3 registry key not found; skipping auto-hide configuration'
        Write-Warning $msg
        $null = $warnings.Add($msg)
    }

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    Write-Host "`nTaskbar configuration complete." -ForegroundColor Green

    return [PSCustomObject]@{
        Success  = $true
        Changes  = $changes.ToArray()
        Warnings = $warnings.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Set-TaskbarConfig'
)
