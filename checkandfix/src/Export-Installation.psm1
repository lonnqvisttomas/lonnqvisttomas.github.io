# Export-Installation.psm1 — USB and ISO export orchestration functions
#
# Provides the top-level orchestration for exporting a Windows installation
# to USB media (via diskpart + robocopy + bootsect/bcdboot) or to an ISO
# image (via oscdimg).
#
# Dependencies (loaded as NestedModules in the same manifest):
#   Write-BootableMedia.psm1 — New-DiskpartScript, Invoke-Diskpart,
#       Copy-InstallationFiles, Set-BootConfiguration, Find-Oscdimg,
#       Confirm-DriveSelection
#   Repair-WindowsImage.psm1 — Invoke-ExternalCommand, Write-StepResult
#
# Requires: PowerShell 5.1+, Administrator privileges for disk operations.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Export-ToUSB — Create bootable USB from a Windows installation source
# ---------------------------------------------------------------------------

function Export-ToUSB {
    <#
    .SYNOPSIS
        Exports a Windows installation to a USB drive, making it bootable.

    .DESCRIPTION
        Orchestrates the full USB export workflow:
          1. Confirms the user intends to wipe the target disk/drive.
          2. Prepares the USB drive using diskpart (clean, create partition,
             format FAT32, assign letter).
          3. Copies the installation files via robocopy.
          4. Configures the boot sector/BCD on the target drive.

        Returns a structured result object with per-step outcomes.

    .PARAMETER DiskNumber
        The disk number of the target USB drive (as shown by diskpart
        list disk). Example: 2.

    .PARAMETER DriveLetter
        The drive letter to assign to the USB partition, including the
        colon. Example: "E:".

    .PARAMETER SourcePath
        Path to the Windows installation source. Defaults to the system
        drive root (e.g., "C:\").

    .EXAMPLE
        $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:'
        if ($result.Success) { Write-Host 'USB export completed.' }

    .EXAMPLE
        Export-ToUSB -DiskNumber 3 -DriveLetter 'F:' -SourcePath 'D:\' -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Success, Steps, ExportTarget, StartTime,
        EndTime, Duration
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [int]$DiskNumber,

        [Parameter(Mandatory = $true)]
        [string]$DriveLetter,

        [Parameter()]
        [string]$SourcePath = "$env:SystemDrive\"
    )

    $exportStartTime = Get-Date
    $steps = [System.Collections.ArrayList]::new()

    Write-StepResult -Message "Starting USB export to disk $DiskNumber ($DriveLetter) from source '$SourcePath'" -Status 'Info' -Timestamp $exportStartTime

    # ------------------------------------------------------------------
    # Step 1: Confirm drive selection with the user
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Step 1/4: Confirming drive selection' -Status 'Info'

    $confirmed = Confirm-DriveSelection -DiskNumber $DiskNumber -DriveLetter $DriveLetter
    $null = $steps.Add([PSCustomObject]@{
        Name    = 'Confirm Drive Selection'
        Success = $confirmed
    })

    if (-not $confirmed) {
        Write-StepResult -Message 'Drive selection was not confirmed — aborting USB export' -Status 'Warning'

        $exportEndTime = Get-Date
        return [PSCustomObject]@{
            Success      = $false
            Steps        = $steps.ToArray()
            ExportTarget = 'USB'
            StartTime    = $exportStartTime
            EndTime      = $exportEndTime
            Duration     = $exportEndTime - $exportStartTime
        }
    }

    Write-StepResult -Message 'Drive selection confirmed' -Status 'Pass'

    # ------------------------------------------------------------------
    # Step 2: Prepare the USB drive via diskpart
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Step 2/4: Preparing USB drive via diskpart' -Status 'Info'

    $scriptPath = New-DiskpartScript -DiskNumber $DiskNumber -DriveLetter $DriveLetter

    if ($PSCmdlet.ShouldProcess("Disk $DiskNumber", 'Run diskpart to prepare USB drive')) {
        $diskpartResult = Invoke-Diskpart -ScriptPath $scriptPath
    }
    else {
        Write-StepResult -Message "WhatIf: Would run diskpart on disk $DiskNumber" -Status 'Info'
        $diskpartResult = [PSCustomObject]@{
            Success = $true
        }
    }

    $null = $steps.Add([PSCustomObject]@{
        Name    = 'Diskpart Preparation'
        Success = $diskpartResult.Success
        Result  = $diskpartResult
    })

    if (-not $diskpartResult.Success) {
        Write-StepResult -Message 'Diskpart preparation failed — aborting USB export' -Status 'Fail'

        $exportEndTime = Get-Date
        return [PSCustomObject]@{
            Success      = $false
            Steps        = $steps.ToArray()
            ExportTarget = 'USB'
            StartTime    = $exportStartTime
            EndTime      = $exportEndTime
            Duration     = $exportEndTime - $exportStartTime
        }
    }

    Write-StepResult -Message 'Diskpart preparation completed successfully' -Status 'Pass'

    # ------------------------------------------------------------------
    # Step 3: Copy installation files to the USB drive
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Step 3/4: Copying installation files' -Status 'Info'

    if ($PSCmdlet.ShouldProcess("$SourcePath -> $DriveLetter", 'Copy installation files to USB drive')) {
        $copyResult = Copy-InstallationFiles -SourcePath $SourcePath -DestinationPath $DriveLetter
    }
    else {
        Write-StepResult -Message "WhatIf: Would copy files from '$SourcePath' to '$DriveLetter'" -Status 'Info'
        $copyResult = [PSCustomObject]@{
            Success = $true
        }
    }

    $null = $steps.Add([PSCustomObject]@{
        Name    = 'Copy Installation Files'
        Success = $copyResult.Success
        Result  = $copyResult
    })

    if (-not $copyResult.Success) {
        Write-StepResult -Message 'File copy failed — aborting USB export' -Status 'Fail'

        $exportEndTime = Get-Date
        return [PSCustomObject]@{
            Success      = $false
            Steps        = $steps.ToArray()
            ExportTarget = 'USB'
            StartTime    = $exportStartTime
            EndTime      = $exportEndTime
            Duration     = $exportEndTime - $exportStartTime
        }
    }

    Write-StepResult -Message 'Installation files copied successfully' -Status 'Pass'

    # ------------------------------------------------------------------
    # Step 4: Configure boot on the target drive
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Step 4/4: Configuring boot on target drive' -Status 'Info'

    if ($PSCmdlet.ShouldProcess($DriveLetter, 'Configure boot on USB drive')) {
        $bootResult = Set-BootConfiguration -SourcePath $SourcePath -TargetDrive $DriveLetter
    }
    else {
        Write-StepResult -Message "WhatIf: Would configure boot on '$DriveLetter'" -Status 'Info'
        $bootResult = [PSCustomObject]@{
            Success = $true
        }
    }

    $null = $steps.Add([PSCustomObject]@{
        Name    = 'Boot Configuration'
        Success = $bootResult.Success
        Result  = $bootResult
    })

    if (-not $bootResult.Success) {
        Write-StepResult -Message 'Boot configuration failed' -Status 'Fail'

        $exportEndTime = Get-Date
        return [PSCustomObject]@{
            Success      = $false
            Steps        = $steps.ToArray()
            ExportTarget = 'USB'
            StartTime    = $exportStartTime
            EndTime      = $exportEndTime
            Duration     = $exportEndTime - $exportStartTime
        }
    }

    Write-StepResult -Message 'Boot configuration completed successfully' -Status 'Pass'

    # ------------------------------------------------------------------
    # Summary
    # ------------------------------------------------------------------
    $exportEndTime = Get-Date
    $exportDuration = $exportEndTime - $exportStartTime

    Write-StepResult -Message "USB export completed successfully (duration: $($exportDuration.ToString()))" -Status 'Pass' -Timestamp $exportEndTime

    return [PSCustomObject]@{
        Success      = $true
        Steps        = $steps.ToArray()
        ExportTarget = 'USB'
        StartTime    = $exportStartTime
        EndTime      = $exportEndTime
        Duration     = $exportDuration
    }
}

# ---------------------------------------------------------------------------
# Export-ToISO — Create bootable ISO from a Windows installation source
# ---------------------------------------------------------------------------

function Export-ToISO {
    <#
    .SYNOPSIS
        Creates a bootable ISO image from a Windows installation source.

    .DESCRIPTION
        Uses oscdimg.exe (from the Windows ADK) to create a dual-boot
        (BIOS + UEFI) ISO image. If oscdimg is not found, the function
        returns a result with guidance on how to install the Windows ADK.

    .PARAMETER SourcePath
        Path to the Windows installation source. Defaults to the system
        drive root (e.g., "C:\").

    .PARAMETER OutputPath
        Path for the output ISO file. Defaults to
        "$env:USERPROFILE\Desktop\WindowsBackup.iso".

    .EXAMPLE
        $result = Export-ToISO
        if ($result.Success) { Write-Host "ISO created at $($result.OutputPath)" }

    .EXAMPLE
        Export-ToISO -SourcePath 'D:\WinInstall' -OutputPath 'E:\backup.iso'

    .OUTPUTS
        PSCustomObject with properties: Success, OutputPath, ExportTarget,
        OscdimgPath, StartTime, EndTime, Duration. If oscdimg is not found,
        also includes GuidanceMessage.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$SourcePath = "$env:SystemDrive\",

        [Parameter()]
        [string]$OutputPath = "$env:USERPROFILE\Desktop\WindowsBackup.iso"
    )

    $exportStartTime = Get-Date

    Write-StepResult -Message "Starting ISO export from source '$SourcePath' to '$OutputPath'" -Status 'Info' -Timestamp $exportStartTime

    # ------------------------------------------------------------------
    # Step 1: Locate oscdimg.exe
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Locating oscdimg.exe' -Status 'Info'

    $oscdimgPath = Find-Oscdimg

    if ($null -eq $oscdimgPath) {
        $adkUrl = 'https://go.microsoft.com/fwlink/?linkid=2243390'
        $guidanceMessage = @(
            'oscdimg.exe was not found on this system.',
            'To create ISO images, install the Windows Assessment and Deployment Kit (ADK):',
            "  Download: $adkUrl",
            '  During installation, select the "Deployment Tools" feature.',
            'After installation, re-run this command.'
        ) -join [Environment]::NewLine

        Write-StepResult -Message 'oscdimg.exe not found' -Status 'Fail'
        Write-StepResult -Message $guidanceMessage -Status 'Info'

        $exportEndTime = Get-Date
        return [PSCustomObject]@{
            Success         = $false
            OutputPath      = $OutputPath
            ExportTarget    = 'ISO'
            OscdimgPath     = $null
            GuidanceMessage = $guidanceMessage
            StartTime       = $exportStartTime
            EndTime         = $exportEndTime
            Duration        = $exportEndTime - $exportStartTime
        }
    }

    Write-StepResult -Message "Found oscdimg.exe at '$oscdimgPath'" -Status 'Pass'

    # ------------------------------------------------------------------
    # Step 2: Ensure the output directory exists
    # ------------------------------------------------------------------
    $outputDir = Split-Path -Path $OutputPath -Parent
    if (-not [string]::IsNullOrEmpty($outputDir)) {
        if (-not (Test-Path -Path $outputDir -PathType Container)) {
            Write-StepResult -Message "Creating output directory '$outputDir'" -Status 'Info'
            try {
                $null = New-Item -Path $outputDir -ItemType Directory -Force
            }
            catch {
                Write-StepResult -Message "Failed to create output directory: $($_.Exception.Message)" -Status 'Fail'

                $exportEndTime = Get-Date
                return [PSCustomObject]@{
                    Success      = $false
                    OutputPath   = $OutputPath
                    ExportTarget = 'ISO'
                    OscdimgPath  = $oscdimgPath
                    StartTime    = $exportStartTime
                    EndTime      = $exportEndTime
                    Duration     = $exportEndTime - $exportStartTime
                }
            }
        }
    }

    # ------------------------------------------------------------------
    # Step 3: Build oscdimg arguments and create the ISO
    # ------------------------------------------------------------------
    Write-StepResult -Message 'Creating bootable ISO image (BIOS + UEFI)' -Status 'Info'

    # Construct the -bootdata argument for dual-boot support:
    #   Entry 1: BIOS boot using etfsboot.com
    #   Entry 2: UEFI boot using efisys.bin
    $biosBootFile = Join-Path -Path $SourcePath -ChildPath 'boot\etfsboot.com'
    $uefiBootFile = Join-Path -Path $SourcePath -ChildPath 'efi\microsoft\boot\efisys.bin'

    $bootdataValue = "2#p0,e,b`"$biosBootFile`"#pEF,e,b`"$uefiBootFile`""

    $oscdimgArgs = @(
        '-m'
        '-o'
        '-u2'
        '-udfver102'
        "-bootdata:$bootdataValue"
        $SourcePath
        $OutputPath
    )

    $oscdimgResult = Invoke-ExternalCommand `
        -FilePath $oscdimgPath `
        -ArgumentList $oscdimgArgs `
        -Description "Create bootable ISO at '$OutputPath'"

    # ------------------------------------------------------------------
    # Result
    # ------------------------------------------------------------------
    $exportEndTime = Get-Date
    $exportDuration = $exportEndTime - $exportStartTime

    if ($oscdimgResult.Success) {
        Write-StepResult -Message "ISO image created successfully at '$OutputPath' (duration: $($exportDuration.ToString()))" -Status 'Pass' -Timestamp $exportEndTime
    }
    else {
        Write-StepResult -Message "ISO creation failed (exit code $($oscdimgResult.ExitCode), duration: $($exportDuration.ToString()))" -Status 'Fail' -Timestamp $exportEndTime
    }

    return [PSCustomObject]@{
        Success      = $oscdimgResult.Success
        OutputPath   = $OutputPath
        ExportTarget = 'ISO'
        OscdimgPath  = $oscdimgPath
        ExitCode     = $oscdimgResult.ExitCode
        Output       = $oscdimgResult.Output
        StartTime    = $exportStartTime
        EndTime      = $exportEndTime
        Duration     = $exportDuration
    }
}

# ---------------------------------------------------------------------------
# Start-ExportPipeline — Top-level dispatcher for USB or ISO export
# ---------------------------------------------------------------------------

function Start-ExportPipeline {
    <#
    .SYNOPSIS
        Orchestrates the export of a Windows installation to USB or ISO.

    .DESCRIPTION
        Top-level entry point that dispatches to Export-ToUSB or Export-ToISO
        based on the ExportTarget parameter. Validates that USB-specific
        parameters (DiskNumber, DriveLetter) are provided when exporting
        to USB.

    .PARAMETER ExportTarget
        The type of export to perform. Must be 'USB' or 'ISO'.

    .PARAMETER DiskNumber
        The disk number of the target USB drive. Required when ExportTarget
        is 'USB'.

    .PARAMETER DriveLetter
        The drive letter for the target USB partition (e.g., "E:"). Required
        when ExportTarget is 'USB'.

    .PARAMETER SourcePath
        Path to the Windows installation source. Defaults to the system
        drive root (e.g., "C:\").

    .PARAMETER OutputPath
        Path for the output ISO file. Only used when ExportTarget is 'ISO'.
        Defaults to "$env:USERPROFILE\Desktop\WindowsBackup.iso".

    .EXAMPLE
        Start-ExportPipeline -ExportTarget USB -DiskNumber 2 -DriveLetter 'E:'

    .EXAMPLE
        Start-ExportPipeline -ExportTarget ISO -OutputPath 'D:\backup.iso'

    .EXAMPLE
        Start-ExportPipeline -ExportTarget USB -DiskNumber 1 -DriveLetter 'F:' -WhatIf

    .OUTPUTS
        PSCustomObject — the result from the dispatched export function
        (Export-ToUSB or Export-ToISO).
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('USB', 'ISO')]
        [string]$ExportTarget,

        [Parameter()]
        [int]$DiskNumber,

        [Parameter()]
        [string]$DriveLetter,

        [Parameter()]
        [string]$SourcePath = "$env:SystemDrive\",

        [Parameter()]
        [string]$OutputPath
    )

    Write-StepResult -Message "Starting export pipeline — target: $ExportTarget" -Status 'Info'

    $result = $null

    switch ($ExportTarget) {
        'USB' {
            # ----------------------------------------------------------
            # Validate USB-required parameters
            # ----------------------------------------------------------
            if (-not $PSBoundParameters.ContainsKey('DiskNumber')) {
                throw 'The -DiskNumber parameter is required when ExportTarget is USB.'
            }

            if (-not $PSBoundParameters.ContainsKey('DriveLetter') -or [string]::IsNullOrEmpty($DriveLetter)) {
                throw 'The -DriveLetter parameter is required when ExportTarget is USB.'
            }

            # ----------------------------------------------------------
            # Dispatch to Export-ToUSB
            # ----------------------------------------------------------
            $usbSplat = @{
                DiskNumber  = $DiskNumber
                DriveLetter = $DriveLetter
                SourcePath  = $SourcePath
            }

            $result = Export-ToUSB @usbSplat
        }

        'ISO' {
            # ----------------------------------------------------------
            # Dispatch to Export-ToISO
            # ----------------------------------------------------------
            $isoSplat = @{
                SourcePath = $SourcePath
            }

            if ($PSBoundParameters.ContainsKey('OutputPath') -and -not [string]::IsNullOrEmpty($OutputPath)) {
                $isoSplat['OutputPath'] = $OutputPath
            }

            $result = Export-ToISO @isoSplat
        }
    }

    # ------------------------------------------------------------------
    # Log final outcome
    # ------------------------------------------------------------------
    if ($null -ne $result) {
        if ($result.Success) {
            Write-StepResult -Message "$ExportTarget export completed successfully" -Status 'Pass'
        }
        else {
            Write-StepResult -Message "$ExportTarget export failed" -Status 'Fail'
        }
    }

    return $result
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Export-ToUSB',
    'Export-ToISO',
    'Start-ExportPipeline'
)
