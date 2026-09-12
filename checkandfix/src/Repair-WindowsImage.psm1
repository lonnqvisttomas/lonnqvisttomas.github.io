# Repair-WindowsImage.psm1 — DISM/SFC repair pipeline functions
#
# Provides a structured repair pipeline that orchestrates DISM CheckHealth,
# ScanHealth, RestoreHealth, and SFC /scannow in sequence with full logging,
# WhatIf support, and error-handling control.
#
# Requires: PowerShell 5.1+, Administrator privileges for DISM/SFC execution.

Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# Write-StepResult — Standardized timestamped, color-coded console output
# ---------------------------------------------------------------------------

function Write-StepResult {
    <#
    .SYNOPSIS
        Writes a timestamped, color-coded status message to the console.

    .DESCRIPTION
        Produces structured console output in the format:
        [yyyy-MM-dd HH:mm:ss] [STATUS] Message

        Colors are mapped to status values:
          Pass    -> Green
          Fail    -> Red
          Warning -> Yellow
          Info    -> Cyan

    .PARAMETER Message
        The message text to display.

    .PARAMETER Status
        The status label. Must be one of: Pass, Fail, Info, Warning.

    .PARAMETER Timestamp
        Optional datetime for the log line. Defaults to the current time.

    .EXAMPLE
        Write-StepResult -Message 'DISM CheckHealth completed' -Status 'Pass'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$Message,

        [Parameter(Mandatory = $true, Position = 1)]
        [ValidateSet('Pass', 'Fail', 'Info', 'Warning')]
        [string]$Status,

        [Parameter()]
        [datetime]$Timestamp
    )

    if (-not $PSBoundParameters.ContainsKey('Timestamp')) {
        $Timestamp = Get-Date
    }

    $colorMap = @{
        'Pass'    = 'Green'
        'Fail'    = 'Red'
        'Warning' = 'Yellow'
        'Info'    = 'Cyan'
    }

    $color = $colorMap[$Status]
    $ts = $Timestamp.ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts] [$Status] $Message"

    Write-Host $line -ForegroundColor $color
}

# ---------------------------------------------------------------------------
# Invoke-ExternalCommand — Unified wrapper for invoking external executables
# ---------------------------------------------------------------------------

function Invoke-ExternalCommand {
    <#
    .SYNOPSIS
        Invokes an external executable with structured result capture.

    .DESCRIPTION
        Unified wrapper that runs an external process, captures its exit code
        and output, measures execution duration, and returns a result object.

        Supports -WhatIf: when active, logs what would run and returns a
        synthetic success result without actually executing the command.

        The SuccessPredicate scriptblock receives the exit code and returns
        $true if the exit code should be considered successful.

    .PARAMETER FilePath
        Path or name of the executable to invoke.

    .PARAMETER ArgumentList
        Array of arguments to pass to the executable.

    .PARAMETER Description
        Human-readable description of the operation for logging.

    .PARAMETER SuccessPredicate
        Scriptblock that receives the exit code and returns $true/$false.
        Defaults to { param($code) $code -eq 0 }.

    .EXAMPLE
        Invoke-ExternalCommand -FilePath 'dism.exe' -ArgumentList @('/Online', '/Cleanup-Image', '/CheckHealth') -Description 'DISM CheckHealth'

    .OUTPUTS
        PSCustomObject with properties: ExitCode, Success, Output, Command, Duration
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$FilePath,

        [Parameter(Position = 1)]
        [string[]]$ArgumentList = @(),

        [Parameter()]
        [string]$Description,

        [Parameter()]
        [scriptblock]$SuccessPredicate = { param($code) $code -eq 0 }
    )

    # Build the full command string for logging
    $commandLine = $FilePath
    if ($ArgumentList.Count -gt 0) {
        $commandLine = "$FilePath $($ArgumentList -join ' ')"
    }

    # Default description to the command line if not provided
    if ([string]::IsNullOrEmpty($Description)) {
        $Description = $commandLine
    }

    # WhatIf support: log what would run, return synthetic success
    if (-not $PSCmdlet.ShouldProcess($commandLine, $Description)) {
        Write-StepResult -Message "WhatIf: Would run: $commandLine" -Status 'Info'

        return [PSCustomObject]@{
            ExitCode  = 0
            Success   = $true
            Output    = ''
            Command   = $commandLine
            Duration  = [TimeSpan]::Zero
        }
    }

    $startTime = Get-Date
    Write-StepResult -Message "Starting: $Description" -Status 'Info' -Timestamp $startTime
    Write-StepResult -Message "Command: $commandLine" -Status 'Info' -Timestamp $startTime

    # Execute the command and capture output
    $output = $null
    try {
        if ($ArgumentList.Count -gt 0) {
            $output = & $FilePath $ArgumentList 2>&1 | Out-String
        }
        else {
            $output = & $FilePath 2>&1 | Out-String
        }
    }
    catch {
        $output = $_.Exception.Message
    }

    # Guard against $LASTEXITCODE not being set (can happen when the call
    # operator does not invoke a native executable, e.g. in mocked tests or
    # when the executable is not found).  Use Get-Variable to avoid a
    # StrictMode violation.
    $exitCodeVar = Get-Variable -Name 'LASTEXITCODE' -Scope Global -ErrorAction SilentlyContinue
    $exitCode = if ($null -ne $exitCodeVar -and $null -ne $exitCodeVar.Value) { $exitCodeVar.Value } else { -1 }

    $endTime = Get-Date
    $duration = $endTime - $startTime

    # Evaluate success using the predicate
    $success = $false
    try {
        $success = [bool](& $SuccessPredicate $exitCode)
    }
    catch {
        $success = $false
    }

    # Log completion
    if ($success) {
        Write-StepResult -Message "Completed: $Description (exit code $exitCode, duration $($duration.ToString()))" -Status 'Pass' -Timestamp $endTime
    }
    else {
        Write-StepResult -Message "Failed: $Description (exit code $exitCode, duration $($duration.ToString()))" -Status 'Fail' -Timestamp $endTime
    }

    return [PSCustomObject]@{
        ExitCode  = $exitCode
        Success   = $success
        Output    = $output
        Command   = $commandLine
        Duration  = $duration
    }
}

# ---------------------------------------------------------------------------
# Invoke-DISMCheckHealth — DISM /CheckHealth wrapper
# ---------------------------------------------------------------------------

function Invoke-DISMCheckHealth {
    <#
    .SYNOPSIS
        Runs DISM /Online /Cleanup-Image /CheckHealth.

    .DESCRIPTION
        Quickly checks whether the Windows component store has any corruption
        markers. This is a fast, non-repairing check.

    .EXAMPLE
        $result = Invoke-DISMCheckHealth
        if (-not $result.Success) { Write-Warning 'CheckHealth reported issues.' }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $splat = @{
        FilePath     = 'dism.exe'
        ArgumentList = @('/Online', '/Cleanup-Image', '/CheckHealth')
        Description  = 'DISM CheckHealth'
    }

    Invoke-ExternalCommand @splat
}

# ---------------------------------------------------------------------------
# Invoke-DISMScanHealth — DISM /ScanHealth wrapper
# ---------------------------------------------------------------------------

function Invoke-DISMScanHealth {
    <#
    .SYNOPSIS
        Runs DISM /Online /Cleanup-Image /ScanHealth.

    .DESCRIPTION
        Performs a thorough scan of the Windows component store to detect
        corruption. This operation may take several minutes.

    .EXAMPLE
        $result = Invoke-DISMScanHealth
        if (-not $result.Success) { Write-Warning 'ScanHealth detected corruption.' }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $splat = @{
        FilePath     = 'dism.exe'
        ArgumentList = @('/Online', '/Cleanup-Image', '/ScanHealth')
        Description  = 'DISM ScanHealth'
    }

    Invoke-ExternalCommand @splat
}

# ---------------------------------------------------------------------------
# Invoke-DISMRestoreHealth — DISM /RestoreHealth wrapper
# ---------------------------------------------------------------------------

function Invoke-DISMRestoreHealth {
    <#
    .SYNOPSIS
        Runs DISM /Online /Cleanup-Image /RestoreHealth.

    .DESCRIPTION
        Attempts to repair corruption detected in the Windows component store.
        Optionally uses a local repair source and can limit access to Windows
        Update by using the -LimitAccess switch.

    .PARAMETER Source
        Optional path to a local repair source (e.g., a mounted WIM or a
        side-by-side folder). Appended as /Source:<path>.

    .PARAMETER LimitAccess
        When set, appends /LimitAccess to prevent DISM from contacting
        Windows Update for repair files.

    .EXAMPLE
        Invoke-DISMRestoreHealth
    .EXAMPLE
        Invoke-DISMRestoreHealth -Source 'D:\sources\install.wim' -LimitAccess
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [string]$Source,

        [Parameter()]
        [switch]$LimitAccess
    )

    $arguments = @('/Online', '/Cleanup-Image', '/RestoreHealth')

    if (-not [string]::IsNullOrEmpty($Source)) {
        $arguments += "/Source:$Source"
    }

    if ($LimitAccess) {
        $arguments += '/LimitAccess'
    }

    $splat = @{
        FilePath     = 'dism.exe'
        ArgumentList = $arguments
        Description  = 'DISM RestoreHealth'
    }

    Invoke-ExternalCommand @splat
}

# ---------------------------------------------------------------------------
# Invoke-SFCScan — SFC /scannow wrapper
# ---------------------------------------------------------------------------

function Invoke-SFCScan {
    <#
    .SYNOPSIS
        Runs sfc /scannow.

    .DESCRIPTION
        Invokes the System File Checker to scan and repair protected system
        files. Requires Administrator privileges.

    .EXAMPLE
        $result = Invoke-SFCScan
        if ($result.Success) { Write-Host 'SFC completed successfully.' }
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $splat = @{
        FilePath     = 'sfc'
        ArgumentList = @('/scannow')
        Description  = 'SFC Scannow'
    }

    Invoke-ExternalCommand @splat
}

# ---------------------------------------------------------------------------
# Start-RepairPipeline — Full DISM + SFC orchestration
# ---------------------------------------------------------------------------

function Start-RepairPipeline {
    <#
    .SYNOPSIS
        Orchestrates the full DISM/SFC repair pipeline.

    .DESCRIPTION
        Runs the following steps in sequence:
          1. DISM CheckHealth
          2. DISM ScanHealth
          3. DISM RestoreHealth
          4. SFC /scannow

        Individual phases can be skipped via -SkipDISM or -SkipSFC.
        By default, the pipeline stops on the first failure. Use
        -ContinueOnError to run all steps regardless of failures.

    .PARAMETER SkipDISM
        Skip all three DISM steps (CheckHealth, ScanHealth, RestoreHealth).

    .PARAMETER SkipSFC
        Skip the SFC /scannow step.

    .PARAMETER ContinueOnError
        Continue executing subsequent steps even if a step fails.

    .PARAMETER Source
        Optional repair source path passed to Invoke-DISMRestoreHealth.

    .PARAMETER LimitAccess
        Passed to Invoke-DISMRestoreHealth to prevent Windows Update access.

    .EXAMPLE
        $result = Start-RepairPipeline
        if ($result.OverallSuccess) { Write-Host 'All repairs completed successfully.' }

    .EXAMPLE
        Start-RepairPipeline -SkipDISM -WhatIf

    .OUTPUTS
        PSCustomObject with properties: Steps, OverallSuccess, StartTime, EndTime, Duration
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter()]
        [switch]$SkipDISM,

        [Parameter()]
        [switch]$SkipSFC,

        [Parameter()]
        [switch]$ContinueOnError,

        [Parameter()]
        [string]$Source,

        [Parameter()]
        [switch]$LimitAccess
    )

    $pipelineStartTime = Get-Date
    $steps = [System.Collections.ArrayList]::new()
    $overallSuccess = $true

    Write-StepResult -Message 'Starting repair pipeline' -Status 'Info' -Timestamp $pipelineStartTime

    # ------------------------------------------------------------------
    # DISM steps
    # ------------------------------------------------------------------
    if (-not $SkipDISM) {
        # Step 1: CheckHealth
        Write-StepResult -Message 'Step 1/4: DISM CheckHealth' -Status 'Info'
        $checkHealthResult = Invoke-DISMCheckHealth
        $null = $steps.Add([PSCustomObject]@{
            Name   = 'DISM CheckHealth'
            Result = $checkHealthResult
        })

        if (-not $checkHealthResult.Success) {
            $overallSuccess = $false
            Write-StepResult -Message 'DISM CheckHealth failed' -Status 'Fail'
            if (-not $ContinueOnError) {
                Write-StepResult -Message 'Pipeline stopped due to failure (use -ContinueOnError to override)' -Status 'Warning'
                $pipelineEndTime = Get-Date
                return [PSCustomObject]@{
                    Steps          = $steps.ToArray()
                    OverallSuccess = $false
                    StartTime      = $pipelineStartTime
                    EndTime        = $pipelineEndTime
                    Duration       = $pipelineEndTime - $pipelineStartTime
                }
            }
        }

        # Step 2: ScanHealth
        Write-StepResult -Message 'Step 2/4: DISM ScanHealth' -Status 'Info'
        $scanHealthResult = Invoke-DISMScanHealth
        $null = $steps.Add([PSCustomObject]@{
            Name   = 'DISM ScanHealth'
            Result = $scanHealthResult
        })

        if (-not $scanHealthResult.Success) {
            $overallSuccess = $false
            Write-StepResult -Message 'DISM ScanHealth failed' -Status 'Fail'
            if (-not $ContinueOnError) {
                Write-StepResult -Message 'Pipeline stopped due to failure (use -ContinueOnError to override)' -Status 'Warning'
                $pipelineEndTime = Get-Date
                return [PSCustomObject]@{
                    Steps          = $steps.ToArray()
                    OverallSuccess = $false
                    StartTime      = $pipelineStartTime
                    EndTime        = $pipelineEndTime
                    Duration       = $pipelineEndTime - $pipelineStartTime
                }
            }
        }

        # Step 3: RestoreHealth
        Write-StepResult -Message 'Step 3/4: DISM RestoreHealth' -Status 'Info'
        $restoreHealthSplat = @{}
        if (-not [string]::IsNullOrEmpty($Source)) {
            $restoreHealthSplat['Source'] = $Source
        }
        if ($LimitAccess) {
            $restoreHealthSplat['LimitAccess'] = $true
        }
        $restoreHealthResult = Invoke-DISMRestoreHealth @restoreHealthSplat
        $null = $steps.Add([PSCustomObject]@{
            Name   = 'DISM RestoreHealth'
            Result = $restoreHealthResult
        })

        if (-not $restoreHealthResult.Success) {
            $overallSuccess = $false
            Write-StepResult -Message 'DISM RestoreHealth failed' -Status 'Fail'
            if (-not $ContinueOnError) {
                Write-StepResult -Message 'Pipeline stopped due to failure (use -ContinueOnError to override)' -Status 'Warning'
                $pipelineEndTime = Get-Date
                return [PSCustomObject]@{
                    Steps          = $steps.ToArray()
                    OverallSuccess = $false
                    StartTime      = $pipelineStartTime
                    EndTime        = $pipelineEndTime
                    Duration       = $pipelineEndTime - $pipelineStartTime
                }
            }
        }
    }
    else {
        Write-StepResult -Message 'Skipping DISM steps (CheckHealth, ScanHealth, RestoreHealth)' -Status 'Info'
    }

    # ------------------------------------------------------------------
    # SFC step
    # ------------------------------------------------------------------
    if (-not $SkipSFC) {
        $stepNumber = if ($SkipDISM) { '1/1' } else { '4/4' }
        Write-StepResult -Message "Step ${stepNumber}: SFC Scannow" -Status 'Info'
        $sfcResult = Invoke-SFCScan
        $null = $steps.Add([PSCustomObject]@{
            Name   = 'SFC Scannow'
            Result = $sfcResult
        })

        if (-not $sfcResult.Success) {
            $overallSuccess = $false
            Write-StepResult -Message 'SFC Scannow failed' -Status 'Fail'
            if (-not $ContinueOnError) {
                Write-StepResult -Message 'Pipeline stopped due to failure (use -ContinueOnError to override)' -Status 'Warning'
            }
        }
    }
    else {
        Write-StepResult -Message 'Skipping SFC step' -Status 'Info'
    }

    # ------------------------------------------------------------------
    # Pipeline summary
    # ------------------------------------------------------------------
    $pipelineEndTime = Get-Date
    $pipelineDuration = $pipelineEndTime - $pipelineStartTime

    if ($overallSuccess) {
        Write-StepResult -Message "Repair pipeline completed successfully (duration: $($pipelineDuration.ToString()))" -Status 'Pass' -Timestamp $pipelineEndTime
    }
    else {
        Write-StepResult -Message "Repair pipeline completed with failures (duration: $($pipelineDuration.ToString()))" -Status 'Warning' -Timestamp $pipelineEndTime
    }

    return [PSCustomObject]@{
        Steps          = $steps.ToArray()
        OverallSuccess = $overallSuccess
        StartTime      = $pipelineStartTime
        EndTime        = $pipelineEndTime
        Duration       = $pipelineDuration
    }
}

# ---------------------------------------------------------------------------
# Module exports
# ---------------------------------------------------------------------------

Export-ModuleMember -Function @(
    'Invoke-ExternalCommand',
    'Write-StepResult',
    'Invoke-DISMCheckHealth',
    'Invoke-DISMScanHealth',
    'Invoke-DISMRestoreHealth',
    'Invoke-SFCScan',
    'Start-RepairPipeline'
)
