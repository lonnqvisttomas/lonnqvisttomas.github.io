# Set-TaskbarConfig.psm1 — Taskbar appearance and behaviour configuration
#
# Auto-hides the taskbar, centers icons, sets small taskbar size, and removes
# the search box, Task View button, and widgets via registry writes.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Set-RegistryValue — Ensure a registry path exists and write a value
# ---------------------------------------------------------------------------

function Set-RegistryValue {
    <#
    .SYNOPSIS
        Creates or updates a single registry value, ensuring the parent key exists.

    .DESCRIPTION
        Checks whether the target registry path exists and creates it when
        necessary. Then sets the named property to the supplied value using
        the specified property type.  All writes are guarded by ShouldProcess
        so they respect -WhatIf / -Confirm.

    .PARAMETER Path
        Full registry path (e.g. 'HKCU:\SOFTWARE\Microsoft\...').

    .PARAMETER Name
        Name of the registry value to set.

    .PARAMETER Value
        Data to write.

    .PARAMETER PropertyType
        Registry value type.  Defaults to 'DWord'.

    .EXAMPLE
        Set-RegistryValue -Path 'HKCU:\SOFTWARE\Test' -Name 'Enabled' -Value 1
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        $Value,

        [Parameter()]
        [string]$PropertyType = 'DWord'
    )

    # Ensure the parent key exists
    if (-not (Test-Path -Path $Path)) {
        if ($PSCmdlet.ShouldProcess($Path, 'Create registry key')) {
            $null = New-Item -Path $Path -Force
            Write-Host "  Created registry key: $Path" -ForegroundColor Cyan
        }
    }

    # Set the value
    if ($PSCmdlet.ShouldProcess("$Path\$Name", "Set to $Value ($PropertyType)")) {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $PropertyType
        Write-Host "  Set $Name = $Value" -ForegroundColor Green
    }
}

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
