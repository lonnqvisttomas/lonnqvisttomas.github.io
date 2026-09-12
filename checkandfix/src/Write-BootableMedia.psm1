# Write-BootableMedia.psm1 — Bootable media creation helper functions
#
# Provides low-level helpers for preparing bootable USB drives and ISO images:
# disk partitioning via diskpart, file copying via robocopy, boot configuration
# via bcdboot, oscdimg discovery, and interactive drive confirmation.
#
# Loaded as a nested module alongside Repair-WindowsImage.psm1 (which exports
# Invoke-ExternalCommand and Write-StepResult).  Those functions are available
# in scope at runtime when the parent manifest imports all nested modules.
#
# Requires: PowerShell 5.1+, Administrator privileges for diskpart/bcdboot.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# New-DiskpartScript — Generate a diskpart automation script
# ---------------------------------------------------------------------------

function New-DiskpartScript {
    <#
    .SYNOPSIS
        Creates a temporary diskpart script file for USB drive preparation.

    .DESCRIPTION
        Generates a temporary text file containing diskpart commands that will:
          1. Select the specified disk
          2. Clean the disk
          3. Convert to GPT partition scheme
          4. Create a primary partition
          5. Format as NTFS (quick) with label "WININSTALL"
          6. Assign a drive letter

        The caller is responsible for deleting the temporary file after use.

    .PARAMETER DiskNumber
        The disk number to target (as shown by 'list disk' in diskpart).

    .EXAMPLE
        $scriptPath = New-DiskpartScript -DiskNumber 2
        # Use $scriptPath with Invoke-Diskpart, then remove the file.

    .OUTPUTS
        System.String — The full path to the generated temporary script file.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$DiskNumber
    )

    # Create a temp file with a .txt extension (diskpart requires a readable text file)
    $basePath = [System.IO.Path]::GetTempFileName()
    $scriptPath = [System.IO.Path]::ChangeExtension($basePath, '.txt')

    # If the renamed path differs from the original temp file, rename it
    if ($scriptPath -ne $basePath) {
        if (Test-Path -LiteralPath $basePath) {
            Rename-Item -LiteralPath $basePath -NewName ([System.IO.Path]::GetFileName($scriptPath)) -Force
        }
    }

    $commands = @(
        "select disk $DiskNumber"
        'clean'
        'convert gpt'
        'create partition primary'
        'format fs=ntfs quick label="WININSTALL"'
        'assign'
    )

    $commands | Out-File -FilePath $scriptPath -Encoding ASCII

    Write-Verbose "Created diskpart script at: $scriptPath"

    return $scriptPath
}

# ---------------------------------------------------------------------------
# Invoke-Diskpart — Execute a diskpart script file
# ---------------------------------------------------------------------------

function Invoke-Diskpart {
    <#
    .SYNOPSIS
        Runs diskpart with the specified script file.

    .DESCRIPTION
        Invokes diskpart.exe using the /s parameter to execute an automated
        script.  Uses Invoke-ExternalCommand for structured result capture,
        WhatIf support, and logging.

        The script file is deleted in a finally block regardless of success
        or failure.

    .PARAMETER ScriptPath
        Path to an existing diskpart script file.  The file must exist.

    .EXAMPLE
        $scriptPath = New-DiskpartScript -DiskNumber 2
        $result = Invoke-Diskpart -ScriptPath $scriptPath

    .OUTPUTS
        PSCustomObject — Result from Invoke-ExternalCommand (ExitCode, Success, Output, Command, Duration).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [ValidateScript({
            if (-not (Test-Path -LiteralPath $_)) {
                throw "Script file not found: $_"
            }
            return $true
        })]
        [string]$ScriptPath
    )

    try {
        $splat = @{
            FilePath     = 'diskpart'
            ArgumentList = @('/s', $ScriptPath)
            Description  = "Diskpart script: $ScriptPath"
        }

        $result = Invoke-ExternalCommand @splat
        return $result
    }
    finally {
        # Clean up the temporary script file
        if (Test-Path -LiteralPath $ScriptPath) {
            try {
                Remove-Item -LiteralPath $ScriptPath -Force -ErrorAction SilentlyContinue
                Write-Verbose "Cleaned up diskpart script: $ScriptPath"
            }
            catch {
                Write-Warning "Failed to remove diskpart script file: $ScriptPath"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Copy-InstallationFiles — Robocopy-based file mirroring
# ---------------------------------------------------------------------------

function Copy-InstallationFiles {
    <#
    .SYNOPSIS
        Copies Windows installation files from source to destination using robocopy.

    .DESCRIPTION
        Uses robocopy with /E (all subdirectories), /MIR (mirror), /R:3 (3 retries),
        and /W:5 (5 second wait between retries) to copy installation files.

        Robocopy uses non-standard exit codes: 0-7 indicate varying degrees of
        success (files copied, extra files, mismatches logged), while 8 and above
        indicate actual failures.  A custom SuccessPredicate handles this.

    .PARAMETER SourcePath
        Path to the source directory containing installation files.

    .PARAMETER DestinationPath
        Path to the destination directory (e.g., root of a USB drive).

    .EXAMPLE
        $result = Copy-InstallationFiles -SourcePath 'D:\WinImage' -DestinationPath 'E:\'

    .OUTPUTS
        PSCustomObject — Result from Invoke-ExternalCommand (ExitCode, Success, Output, Command, Duration).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$DestinationPath
    )

    $splat = @{
        FilePath         = 'robocopy'
        ArgumentList     = @($SourcePath, $DestinationPath, '/E', '/MIR', '/R:3', '/W:5')
        Description      = "Robocopy: $SourcePath -> $DestinationPath"
        SuccessPredicate = { param($code) $code -lt 8 }
    }

    $result = Invoke-ExternalCommand @splat
    return $result
}

# ---------------------------------------------------------------------------
# Set-BootConfiguration — Configure UEFI boot via bcdboot
# ---------------------------------------------------------------------------

function Set-BootConfiguration {
    <#
    .SYNOPSIS
        Configures UEFI boot entries using bcdboot.

    .DESCRIPTION
        Runs bcdboot to create boot configuration data on the target drive.
        Points bcdboot at the Windows directory within the source path and
        writes UEFI boot files to the specified target drive.

    .PARAMETER SourcePath
        Path to the root of the Windows installation (the directory that
        contains a \Windows subfolder).

    .PARAMETER TargetDrive
        Drive letter (with colon) of the target boot volume, e.g. "S:".

    .EXAMPLE
        $result = Set-BootConfiguration -SourcePath 'C:' -TargetDrive 'S:'

    .OUTPUTS
        PSCustomObject — Result from Invoke-ExternalCommand (ExitCode, Success, Output, Command, Duration).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$TargetDrive
    )

    $windowsPath = Join-Path -Path $SourcePath -ChildPath 'Windows'

    $splat = @{
        FilePath     = 'bcdboot'
        ArgumentList = @($windowsPath, '/s', $TargetDrive, '/f', 'UEFI')
        Description  = "BCDBoot: $windowsPath -> $TargetDrive (UEFI)"
    }

    $result = Invoke-ExternalCommand @splat
    return $result
}

# ---------------------------------------------------------------------------
# Find-Oscdimg — Locate oscdimg.exe from Windows ADK installations
# ---------------------------------------------------------------------------

function Find-Oscdimg {
    <#
    .SYNOPSIS
        Searches for oscdimg.exe from the Windows Assessment and Deployment Kit.

    .DESCRIPTION
        Checks several well-known installation paths for oscdimg.exe:
          - Program Files (x86)\Windows Kits\10\...\amd64\Oscdimg\
          - Program Files (x86)\Windows Kits\10\...\x86\Oscdimg\
          - Program Files\Windows Kits\10\...\amd64\Oscdimg\
          - Wildcard search under Program Files (x86)\Windows Kits\*\...

        Returns the full path to the first found instance, or $null if
        oscdimg.exe cannot be located.

    .EXAMPLE
        $oscdimgPath = Find-Oscdimg
        if ($null -eq $oscdimgPath) {
            Write-Error 'oscdimg.exe not found. Install the Windows ADK.'
        }

    .OUTPUTS
        System.String or $null — Full path to oscdimg.exe if found.
    #>
    [CmdletBinding()]
    param()

    $adkSubPath = 'Windows Kits\10\Assessment and Deployment Kit\Deployment Tools'

    # Build the list of specific paths to check
    $searchPaths = @(
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "$adkSubPath\amd64\Oscdimg\oscdimg.exe")
        (Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath "$adkSubPath\x86\Oscdimg\oscdimg.exe")
        (Join-Path -Path $env:ProgramFiles -ChildPath "$adkSubPath\amd64\Oscdimg\oscdimg.exe")
    )

    # Check each specific path first
    foreach ($candidatePath in $searchPaths) {
        Write-Verbose "Searching for oscdimg.exe at: $candidatePath"
        if (Test-Path -LiteralPath $candidatePath) {
            Write-Verbose "Found oscdimg.exe at: $candidatePath"
            return $candidatePath
        }
    }

    # Fall back to wildcard search for any ADK version and architecture
    $wildcardPattern = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Windows Kits\*\Assessment and Deployment Kit\Deployment Tools\*\Oscdimg\oscdimg.exe'
    Write-Verbose "Searching with wildcard pattern: $wildcardPattern"

    $wildcardResults = @(Get-ChildItem -Path $wildcardPattern -ErrorAction SilentlyContinue)
    if ($wildcardResults.Count -gt 0) {
        $foundPath = $wildcardResults[0].FullName
        Write-Verbose "Found oscdimg.exe via wildcard: $foundPath"
        return $foundPath
    }

    Write-Verbose 'oscdimg.exe was not found in any known location.'
    return $null
}

# ---------------------------------------------------------------------------
# Confirm-DriveSelection — Interactive drive confirmation prompt
# ---------------------------------------------------------------------------

function Confirm-DriveSelection {
    <#
    .SYNOPSIS
        Prompts the user to confirm the selected disk for destructive operations.

    .DESCRIPTION
        Displays details about the specified disk and asks the user for
        confirmation before proceeding with destructive operations such as
        formatting.

        When -WhatIf is active, uses ShouldProcess to show what would happen
        and returns $false without prompting.

        In normal mode, uses ShouldContinue to present a confirmation dialog
        to the user.

    .PARAMETER DiskNumber
        The disk number to confirm.

    .PARAMETER DriveLetter
        Optional drive letter associated with the disk, for display purposes.

    .EXAMPLE
        if (Confirm-DriveSelection -DiskNumber 2 -DriveLetter 'E') {
            # Proceed with formatting
        }

    .OUTPUTS
        System.Boolean — $true if the user confirmed, $false otherwise.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [int]$DiskNumber,

        [Parameter(Position = 1)]
        [string]$DriveLetter
    )

    # Build a human-readable description of the target
    $driveDisplay = "Disk $DiskNumber"
    if (-not [string]::IsNullOrEmpty($DriveLetter)) {
        $driveDisplay = "Disk $DiskNumber (Drive $DriveLetter)"
    }

    $operationDescription = "Format and prepare $driveDisplay for bootable media"

    # WhatIf support: ShouldProcess returns $false under -WhatIf, showing
    # what would happen without prompting.
    if (-not $PSCmdlet.ShouldProcess($driveDisplay, $operationDescription)) {
        return $false
    }

    # Display drive details for the user
    Write-StepResult -Message "Target: $driveDisplay" -Status 'Info'
    Write-StepResult -Message 'WARNING: All data on this disk will be permanently erased!' -Status 'Warning'

    # Prompt for explicit confirmation via ShouldContinue
    $confirmQuery = "All data on $driveDisplay will be permanently erased. Do you want to continue?"
    $confirmCaption = 'Confirm Drive Selection'

    $confirmed = $PSCmdlet.ShouldContinue($confirmQuery, $confirmCaption)

    if ($confirmed) {
        Write-StepResult -Message "User confirmed: $driveDisplay" -Status 'Pass'
    }
    else {
        Write-StepResult -Message "User cancelled: $driveDisplay" -Status 'Warning'
    }

    return $confirmed
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function New-DiskpartScript, Invoke-Diskpart, Copy-InstallationFiles, Set-BootConfiguration, Find-Oscdimg, Confirm-DriveSelection
