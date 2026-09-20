# Set-StartMenuConfig.psm1 — Start menu layout and behaviour configuration
#
# Adjusts the Windows 11 Start menu to favour a pin-centric layout (closer
# to macOS Launchpad) and hides the recommended section via registry writes.
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
# Set-StartMenuConfig — Main exported function
# ---------------------------------------------------------------------------

function Set-StartMenuConfig {
    <#
    .SYNOPSIS
        Configures the Windows 11 Start menu to resemble macOS Launchpad.

    .DESCRIPTION
        Applies registry tweaks to the current user hive to make the Start
        menu more pin-centric and less recommendation-heavy:
          - Sets Start_Layout to 1 (more pins, fewer recommendations)
          - Writes a VisiblePlaces binary value that hides the recommended
            section

        Returns a structured result object with Success, Changes, and Warnings
        properties.

    .EXAMPLE
        $result = Set-StartMenuConfig
        if ($result.Success) { Write-Host 'Start menu configured.' }

    .EXAMPLE
        Set-StartMenuConfig -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success (bool), Changes (string[]),
        Warnings (string[]).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $changes  = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    Write-Host "`nConfiguring Start menu settings..." -ForegroundColor Cyan

    $advancedPath      = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $visiblePlacesPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start'

    # ------------------------------------------------------------------
    # 1. More pins layout (closer to macOS Launchpad)
    # ------------------------------------------------------------------
    Write-Host "`n  [1/2] Setting Start menu layout to more pins..." -ForegroundColor Cyan
    Set-RegistryValue -Path $advancedPath -Name 'Start_Layout' -Value 1
    $null = $changes.Add('Start menu layout set to more pins (Start_Layout = 1)')

    # ------------------------------------------------------------------
    # 2. Hide the recommended section via VisiblePlaces binary value
    #
    # VisiblePlaces is a binary blob containing GUIDs for sections that
    # should be visible.  Writing a blob that omits the recommended-section
    # GUID effectively hides it.
    #
    # The binary value encodes two GUIDs:
    #   {86087352-D677-4E27-8A4F-DE89DAEE8F2E}  — hide recommended files
    #   {2CB15B63-6498-4ECF-9B4C-A6FF4DE11F30}  — hide recommended section
    # Each GUID is stored in mixed-endian (standard Windows GUID binary
    # representation): first 3 groups little-endian, last 2 groups big-endian.
    # ------------------------------------------------------------------
    Write-Host "  [2/2] Hiding recommended section..." -ForegroundColor Cyan

    # GUID {86087352-D677-4E27-8A4F-DE89DAEE8F2E} in binary form
    # GUID {2CB15B63-6498-4ECF-9B4C-A6FF4DE11F30} in binary form
    [byte[]]$visiblePlaces = @(
        0x52, 0x73, 0x08, 0x86, 0x77, 0xD6, 0x27, 0x4E,
        0x8A, 0x4F, 0xDE, 0x89, 0xDA, 0xEE, 0x8F, 0x2E,
        0x63, 0x5B, 0xB1, 0x2C, 0x98, 0x64, 0xCF, 0x4E,
        0x9B, 0x4C, 0xA6, 0xFF, 0x4D, 0xE1, 0x1F, 0x30
    )

    Set-RegistryValue -Path $visiblePlacesPath -Name 'VisiblePlaces' -Value $visiblePlaces -PropertyType 'Binary'
    $null = $changes.Add('Recommended section hidden (VisiblePlaces binary value written)')

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    Write-Host "`nStart menu configuration complete." -ForegroundColor Green

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
    'Set-StartMenuConfig'
)
