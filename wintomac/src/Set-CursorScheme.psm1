# Set-CursorScheme.psm1 — Deploy and activate a macOS-style cursor scheme
#
# Copies bundled .cur/.ani cursor files from assets/cursors/ to the user's
# local application data directory, registers them as a Windows cursor
# scheme, and activates the scheme via the SystemParametersInfo P/Invoke API.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Set-CursorScheme — Deploy cursor files and activate the scheme
# ---------------------------------------------------------------------------

function Set-CursorScheme {
    <#
    .SYNOPSIS
        Deploys bundled cursor files and activates them as the system cursor scheme.

    .DESCRIPTION
        Locates .cur and .ani files in the module's assets/cursors/ directory,
        copies them to $env:LOCALAPPDATA\WinToMac\cursors\, registers them as
        a Windows cursor scheme named "WinToMac" in the registry, and activates
        the scheme via the SystemParametersInfo Win32 API.

        Cursor files are mapped to standard Windows cursor types based on their
        filename (e.g., arrow.cur maps to the Arrow cursor, help.ani maps to
        the Help cursor). Cursor types without a matching file are left
        unchanged.

        If no cursor files are found in the assets directory, the function
        returns gracefully with a warning and no changes are made.

    .EXAMPLE
        $result = Set-CursorScheme
        if ($result.Success) { Write-Host "Cursors deployed to $($result.CursorPath)" }

    .EXAMPLE
        Set-CursorScheme -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success, Changes, Warnings, CursorPath
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $changes  = [System.Collections.ArrayList]::new()
    $warnings = [System.Collections.ArrayList]::new()

    # ------------------------------------------------------------------
    # Cursor type mapping — registry value names under
    # HKCU:\Control Panel\Cursors that correspond to standard cursor
    # types. File matching is case-insensitive on the base name.
    # ------------------------------------------------------------------
    $cursorTypes = @(
        'Arrow', 'Help', 'AppStarting', 'Wait', 'Crosshair',
        'IBeam', 'NWPen', 'No', 'SizeNS', 'SizeWE',
        'SizeNWSE', 'SizeNESW', 'SizeAll', 'UpArrow', 'Hand'
    )

    # ------------------------------------------------------------------
    # Step 1: Locate cursor files in assets/cursors/
    # ------------------------------------------------------------------
    $assetsDir = Join-Path -Path $PSScriptRoot -ChildPath '..\assets\cursors'
    $assetsDir = [System.IO.Path]::GetFullPath($assetsDir)

    Write-Host -ForegroundColor Cyan "Looking for cursor files in '$assetsDir'..."

    $cursorFiles = @()
    if (Test-Path -Path $assetsDir -PathType Container) {
        $cursorFiles = @(Get-ChildItem -Path $assetsDir -File -Include '*.cur', '*.ani' -Recurse)
    }

    if ($cursorFiles.Count -eq 0) {
        $msg = "No cursor files (.cur/.ani) found in '$assetsDir'. Skipping cursor deployment."
        Write-Host -ForegroundColor Yellow $msg
        $null = $warnings.Add($msg)

        return [PSCustomObject]@{
            Success    = $true
            Changes    = @()
            Warnings   = $warnings.ToArray()
            CursorPath = $null
        }
    }

    Write-Host -ForegroundColor Green "Found $($cursorFiles.Count) cursor file(s)"

    # ------------------------------------------------------------------
    # Step 2: Create the deployment directory if needed
    # ------------------------------------------------------------------
    $deployDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WinToMac\cursors'

    if (-not (Test-Path -Path $deployDir -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($deployDir, 'Create cursor directory')) {
            $null = New-Item -Path $deployDir -ItemType Directory -Force
            Write-Host -ForegroundColor Green "Created directory '$deployDir'"
            $null = $changes.Add("Created directory '$deployDir'")
        }
    }

    # ------------------------------------------------------------------
    # Step 3: Copy all cursor files to the deployment directory
    # ------------------------------------------------------------------
    foreach ($cursorFile in $cursorFiles) {
        $destPath = Join-Path -Path $deployDir -ChildPath $cursorFile.Name

        if ($PSCmdlet.ShouldProcess($destPath, 'Copy cursor file')) {
            Copy-Item -Path $cursorFile.FullName -Destination $destPath -Force
            Write-Host -ForegroundColor Green "Copied '$($cursorFile.Name)' to '$deployDir'"
            $null = $changes.Add("Copied '$($cursorFile.Name)' to '$destPath'")
        }
    }

    # ------------------------------------------------------------------
    # Step 4: Build a lookup of deployed cursor files by base name
    # ------------------------------------------------------------------
    $cursorLookup = @{}
    foreach ($cursorFile in $cursorFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cursorFile.Name)
        $deployedFilePath = Join-Path -Path $deployDir -ChildPath $cursorFile.Name
        $cursorLookup[$baseName.ToLower()] = $deployedFilePath
    }

    # ------------------------------------------------------------------
    # Step 5: Register the cursor scheme in HKCU
    # ------------------------------------------------------------------
    $cursorsRegPath = 'HKCU:\Control Panel\Cursors'

    # Set the scheme name
    if ($PSCmdlet.ShouldProcess("$cursorsRegPath\(Default)", 'Set cursor scheme name to WinToMac')) {
        Set-ItemProperty -Path $cursorsRegPath -Name '(Default)' -Value 'WinToMac' -Type String
        Write-Host -ForegroundColor Green "Set cursor scheme name to 'WinToMac'"
        $null = $changes.Add("Set cursor scheme name to 'WinToMac'")
    }

    # Map each cursor type to its deployed file (if available)
    $mappedCount = 0
    foreach ($cursorType in $cursorTypes) {
        $lookupKey = $cursorType.ToLower()

        if ($cursorLookup.ContainsKey($lookupKey)) {
            $cursorPath = $cursorLookup[$lookupKey]

            if ($PSCmdlet.ShouldProcess("$cursorsRegPath\$cursorType", "Set cursor to '$cursorPath'")) {
                Set-ItemProperty -Path $cursorsRegPath -Name $cursorType -Value $cursorPath -Type ExpandString
                Write-Host -ForegroundColor Green "Mapped $cursorType -> '$cursorPath'"
                $null = $changes.Add("Mapped $cursorType to '$cursorPath'")
                $mappedCount++
            }
        }
    }

    if ($mappedCount -eq 0) {
        $msg = 'No cursor files matched any standard cursor type names. Cursor types are unchanged.'
        Write-Host -ForegroundColor Yellow $msg
        $null = $warnings.Add($msg)
    }
    else {
        Write-Host -ForegroundColor Cyan "Mapped $mappedCount of $($cursorTypes.Count) cursor types"
    }

    # ------------------------------------------------------------------
    # Step 6: Try HKLM registration (system-wide), fall back gracefully
    # ------------------------------------------------------------------
    $schemesRegPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cursors\Schemes'

    try {
        if ($PSCmdlet.ShouldProcess($schemesRegPath, 'Register WinToMac cursor scheme system-wide')) {
            # Build the scheme value: comma-separated list of cursor paths
            # in the standard order matching the cursor types
            $schemePaths = @()
            foreach ($cursorType in $cursorTypes) {
                $lookupKey = $cursorType.ToLower()
                if ($cursorLookup.ContainsKey($lookupKey)) {
                    $schemePaths += $cursorLookup[$lookupKey]
                }
                else {
                    $schemePaths += ''
                }
            }
            $schemeValue = $schemePaths -join ','

            if (-not (Test-Path -Path $schemesRegPath)) {
                $null = New-Item -Path $schemesRegPath -Force
            }
            Set-ItemProperty -Path $schemesRegPath -Name 'WinToMac' -Value $schemeValue -Type String
            Write-Host -ForegroundColor Green 'Registered WinToMac cursor scheme system-wide (HKLM)'
            $null = $changes.Add('Registered WinToMac cursor scheme in HKLM')
        }
    }
    catch {
        $msg = "Could not register cursor scheme in HKLM (access denied). Using HKCU-only registration."
        Write-Host -ForegroundColor Yellow $msg
        $null = $warnings.Add($msg)
    }

    # ------------------------------------------------------------------
    # Step 7: Activate the cursor scheme via SystemParametersInfo
    # ------------------------------------------------------------------
    # Only load the type definition if it is not already loaded
    if ($null -eq ([Type]::GetType('CursorApi'))) {
        try {
            $cursorApiDef = @'
using System;
using System.Runtime.InteropServices;
public class CursorApi {
    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool SystemParametersInfo(uint uiAction, uint uiParam, string pvParam, uint fWinIni);
    public const uint SPI_SETCURSORS = 0x0057;
    public const uint SPIF_UPDATEINIFILE = 0x01;
    public const uint SPIF_SENDCHANGE = 0x02;
}
'@
            Add-Type -TypeDefinition $cursorApiDef
        }
        catch {
            # Type may already be loaded from a previous import in the same session
            if ($_.Exception.Message -notlike '*already exists*') {
                throw
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('System cursors', 'Activate cursor scheme via SystemParametersInfo')) {
        $spiResult = [CursorApi]::SystemParametersInfo(
            [CursorApi]::SPI_SETCURSORS,
            0,
            $null,
            [CursorApi]::SPIF_SENDCHANGE
        )

        if ($spiResult) {
            Write-Host -ForegroundColor Green 'Cursor scheme activated via SystemParametersInfo'
            $null = $changes.Add('Activated cursor scheme via SystemParametersInfo')
        }
        else {
            $errorCode = [System.Runtime.InteropServices.Marshal]::GetLastWin32Error()
            $msg = "SystemParametersInfo(SPI_SETCURSORS) returned false (Win32 error code: $errorCode)"
            Write-Host -ForegroundColor Yellow $msg
            $null = $warnings.Add($msg)
        }
    }

    # ------------------------------------------------------------------
    # Result
    # ------------------------------------------------------------------
    Write-Host -ForegroundColor Cyan 'Cursor scheme deployment complete.'

    return [PSCustomObject]@{
        Success    = $true
        Changes    = $changes.ToArray()
        Warnings   = $warnings.ToArray()
        CursorPath = $deployDir
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Set-CursorScheme'
)
