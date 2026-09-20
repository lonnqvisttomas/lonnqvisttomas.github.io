# RegistryHelpers.ps1 — Shared registry utility functions
#
# Dot-sourced by Set-TaskbarConfig, Set-StartMenuConfig, and Set-VisualStyle
# modules to provide a single copy of common registry helpers.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

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
