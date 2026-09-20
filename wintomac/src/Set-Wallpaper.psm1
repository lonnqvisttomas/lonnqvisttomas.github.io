# Set-Wallpaper.psm1 — Deploy and apply a macOS-style desktop wallpaper
#
# Copies a bundled wallpaper image from assets/wallpapers/ to the user's
# application data directory and applies it via the SystemParametersInfo
# P/Invoke API.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Set-Wallpaper — Deploy and apply a bundled wallpaper image
# ---------------------------------------------------------------------------

function Set-Wallpaper {
    <#
    .SYNOPSIS
        Deploys a bundled wallpaper image and applies it as the desktop background.

    .DESCRIPTION
        Locates the first image file (.jpg, .png, .bmp) in the module's
        assets/wallpapers/ directory, copies it to
        $env:APPDATA\WinToMac\wallpapers\, sets the desktop wallpaper style
        to Fill via registry, and applies the wallpaper using the
        SystemParametersInfo Win32 API.

        If no wallpaper image is found in the assets directory, the function
        returns gracefully with a warning and no changes are made.

    .EXAMPLE
        $result = Set-Wallpaper
        if ($result.Success) { Write-Host "Wallpaper applied: $($result.WallpaperPath)" }

    .EXAMPLE
        Set-Wallpaper -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success, Changes, Warnings,
        WallpaperPath
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $changes  = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    # ------------------------------------------------------------------
    # Step 1: Locate the first wallpaper image in assets/wallpapers/
    # ------------------------------------------------------------------
    $assetsDir = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\wallpapers'
    $assetsDir = [System.IO.Path]::GetFullPath($assetsDir)

    Write-Host -ForegroundColor Cyan "Looking for wallpaper images in '$assetsDir'..."

    $wallpaperFile = $null
    if (Test-Path -Path $assetsDir -PathType Container) {
        $wallpaperFile = Get-ChildItem -Path $assetsDir -File -Include '*.jpg', '*.png', '*.bmp' -Recurse |
            Select-Object -First 1
    }

    if ($null -eq $wallpaperFile) {
        $msg = "No wallpaper image found in '$assetsDir'. Skipping wallpaper deployment."
        Write-Host -ForegroundColor Yellow $msg
        $null = $warnings.Add($msg)

        return [PSCustomObject]@{
            Success       = $true
            Changes       = @()
            Warnings      = $warnings.ToArray()
            WallpaperPath = $null
        }
    }

    Write-Host -ForegroundColor Green "Found wallpaper: '$($wallpaperFile.Name)'"

    # ------------------------------------------------------------------
    # Step 2: Create the deployment directory if needed
    # ------------------------------------------------------------------
    $deployDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\wallpapers'

    if (-not (Test-Path -Path $deployDir -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($deployDir, 'Create wallpaper directory')) {
            $null = New-Item -Path $deployDir -ItemType Directory -Force
            Write-Host -ForegroundColor Green "Created directory '$deployDir'"
            $null = $changes.Add("Created directory '$deployDir'")
        }
    }

    # ------------------------------------------------------------------
    # Step 3: Copy the wallpaper file to the deployment directory
    # ------------------------------------------------------------------
    $deployedPath = Join-Path -Path $deployDir -ChildPath $wallpaperFile.Name

    if ($PSCmdlet.ShouldProcess($deployedPath, 'Copy wallpaper image')) {
        Copy-Item -Path $wallpaperFile.FullName -Destination $deployedPath -Force
        Write-Host -ForegroundColor Green "Copied wallpaper to '$deployedPath'"
        $null = $changes.Add("Copied '$($wallpaperFile.Name)' to '$deployedPath'")
    }

    # ------------------------------------------------------------------
    # Step 4: Set registry values for Fill style
    # ------------------------------------------------------------------
    $desktopRegPath = 'HKCU:\Control Panel\Desktop'

    if ($PSCmdlet.ShouldProcess($desktopRegPath, 'Set wallpaper style to Fill')) {
        Set-ItemProperty -Path $desktopRegPath -Name 'WallpaperStyle' -Value '10' -Type String
        Set-ItemProperty -Path $desktopRegPath -Name 'TileWallpaper'  -Value '0'  -Type String
        Write-Host -ForegroundColor Green 'Set wallpaper style to Fill (WallpaperStyle=10, TileWallpaper=0)'
        $null = $changes.Add('Set WallpaperStyle=10 (Fill) and TileWallpaper=0')
    }

    # ------------------------------------------------------------------
    # Step 5: Apply the wallpaper via SystemParametersInfo P/Invoke
    # ------------------------------------------------------------------
    # Only load the type definition if it is not already loaded
    if ($null -eq ([Type]::GetType('Win32Api'))) {
        try {
            $win32ApiDef = @'
using System;
using System.Runtime.InteropServices;
public class Win32Api {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
    public const uint SPI_SETDESKWALLPAPER = 0x0014;
    public const uint SPI_SETCURSORS = 0x0057;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
}
'@
            Add-Type -TypeDefinition $win32ApiDef
        }
        catch {
            # Type may already be loaded from a previous import in the same session
            if ($_.Exception.Message -notlike '*already exists*') {
                throw
            }
        }
    }

    if ($PSCmdlet.ShouldProcess($deployedPath, 'Apply wallpaper via SystemParametersInfo')) {
        $spiResult = [Win32Api]::SystemParametersInfo(
            [Win32Api]::SPI_SETDESKWALLPAPER,
            0,
            $deployedPath,
            [Win32Api]::SPIF_UPDATEINIFILE -bor [Win32Api]::SPIF_SENDCHANGE
        )

        if ($spiResult) {
            Write-Host -ForegroundColor Green "Wallpaper applied successfully via SystemParametersInfo"
            $null = $changes.Add("Applied wallpaper '$deployedPath' via SystemParametersInfo")
        }
        else {
            $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $msg = "SystemParametersInfo returned false (Win32 error code: $errorCode)"
            Write-Host -ForegroundColor Yellow $msg
            $null = $warnings.Add($msg)
        }
    }

    # ------------------------------------------------------------------
    # Result
    # ------------------------------------------------------------------
    Write-Host -ForegroundColor Cyan 'Wallpaper deployment complete.'

    return [PSCustomObject]@{
        Success       = $true
        Changes       = $changes.ToArray()
        Warnings      = $warnings.ToArray()
        WallpaperPath = $deployedPath
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Set-Wallpaper'
)
