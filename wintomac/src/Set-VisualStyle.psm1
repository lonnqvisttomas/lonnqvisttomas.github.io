# Set-VisualStyle.psm1 — Visual-style and colour configuration
#
# Toggles dark mode, sets a macOS-inspired blue accent colour, enables
# transparency, and configures the title-bar accent colour via registry
# writes.
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
# Set-VisualStyle — Main exported function
# ---------------------------------------------------------------------------

function Set-VisualStyle {
    <#
    .SYNOPSIS
        Applies macOS-inspired visual styling to Windows 11.

    .DESCRIPTION
        Configures the current user's theme and accent settings to approximate
        the macOS dark-mode look:
          - Enables dark mode for apps and the system chrome
          - Enables transparency effects
          - Shows the accent colour on title bars (ColorPrevalence)
          - Sets the accent colour to a macOS-like blue (#0078D4, stored as
            ABGR 0x00D47800 in the registry)
          - Writes an AccentPalette binary blob with eight macOS-inspired
            blue shades

        Returns a structured result object with Success, Changes, and Warnings
        properties.

    .EXAMPLE
        $result = Set-VisualStyle
        if ($result.Success) { Write-Host 'Visual style applied.' }

    .EXAMPLE
        Set-VisualStyle -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success (bool), Changes (string[]),
        Warnings (string[]).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $changes  = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    Write-Host "`nConfiguring visual style settings..." -ForegroundColor Cyan

    $personalizePath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $accentPath      = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent'

    # ------------------------------------------------------------------
    # 1. Dark mode for apps
    # ------------------------------------------------------------------
    Write-Host "`n  [1/6] Enabling dark mode for apps..." -ForegroundColor Cyan
    Set-RegistryValue -Path $personalizePath -Name 'AppsUseLightTheme' -Value 0
    $null = $changes.Add('Dark mode enabled for apps (AppsUseLightTheme = 0)')

    # ------------------------------------------------------------------
    # 2. Dark mode for system chrome
    # ------------------------------------------------------------------
    Write-Host "  [2/6] Enabling dark mode for system..." -ForegroundColor Cyan
    Set-RegistryValue -Path $personalizePath -Name 'SystemUsesLightTheme' -Value 0
    $null = $changes.Add('Dark mode enabled for system (SystemUsesLightTheme = 0)')

    # ------------------------------------------------------------------
    # 3. Enable transparency
    # ------------------------------------------------------------------
    Write-Host "  [3/6] Enabling transparency effects..." -ForegroundColor Cyan
    Set-RegistryValue -Path $personalizePath -Name 'EnableTransparency' -Value 1
    $null = $changes.Add('Transparency effects enabled (EnableTransparency = 1)')

    # ------------------------------------------------------------------
    # 4. Show accent colour on title bars
    # ------------------------------------------------------------------
    Write-Host "  [4/6] Enabling accent colour on title bars..." -ForegroundColor Cyan
    Set-RegistryValue -Path $personalizePath -Name 'ColorPrevalence' -Value 1
    $null = $changes.Add('Accent colour shown on title bars (ColorPrevalence = 1)')

    # ------------------------------------------------------------------
    # 5. Set macOS-like blue accent colour (RGB #0078D4 -> ABGR 0xD47800)
    # ------------------------------------------------------------------
    Write-Host "  [5/6] Setting macOS-inspired blue accent colour..." -ForegroundColor Cyan
    Set-RegistryValue -Path $accentPath -Name 'AccentColorMenu' -Value 0xD47800
    $null = $changes.Add('Accent colour set to macOS blue (AccentColorMenu = 0xD47800, RGB #0078D4)')

    # ------------------------------------------------------------------
    # 6. Write AccentPalette binary blob with macOS-inspired blue shades
    #
    # The palette is 32 bytes: 8 ABGR colour entries of 4 bytes each,
    # progressing from lightest to darkest macOS-inspired blues.
    #
    #   Shade 1 (lightest): #B4D6FA -> ABGR FA D6 B4 00
    #   Shade 2:            #84B8F0 -> ABGR F0 B8 84 00
    #   Shade 3:            #429CE6 -> ABGR E6 9C 42 00
    #   Shade 4:            #0078D4 -> ABGR D4 78 00 00
    #   Shade 5:            #005FA3 -> ABGR A3 5F 00 00
    #   Shade 6:            #004578 -> ABGR 78 45 00 00
    #   Shade 7:            #002D4F -> ABGR 4F 2D 00 00
    #   Shade 8 (darkest):  #00182B -> ABGR 2B 18 00 00
    # ------------------------------------------------------------------
    Write-Host "  [6/6] Writing accent palette..." -ForegroundColor Cyan

    [byte[]]$accentPalette = @(
        0xFA, 0xD6, 0xB4, 0x00,   # Shade 1 — lightest
        0xF0, 0xB8, 0x84, 0x00,   # Shade 2
        0xE6, 0x9C, 0x42, 0x00,   # Shade 3
        0xD4, 0x78, 0x00, 0x00,   # Shade 4 — primary (#0078D4)
        0xA3, 0x5F, 0x00, 0x00,   # Shade 5
        0x78, 0x45, 0x00, 0x00,   # Shade 6
        0x4F, 0x2D, 0x00, 0x00,   # Shade 7
        0x2B, 0x18, 0x00, 0x00    # Shade 8 — darkest
    )

    Set-RegistryValue -Path $accentPath -Name 'AccentPalette' -Value $accentPalette -PropertyType 'Binary'
    $null = $changes.Add('Accent palette set to macOS-inspired blue shades (AccentPalette, 32 bytes)')

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    Write-Host "`nVisual style configuration complete." -ForegroundColor Green

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
    'Set-VisualStyle'
)
