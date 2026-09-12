#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows system repair and installation export utility.

.DESCRIPTION
    Automates the standard Windows repair workflow — running DISM health checks
    and restoration followed by SFC scans — in a single guided execution flow.
    Optionally exports the current Windows installation to a bootable USB drive
    or ISO image.

.PARAMETER SkipDISM
    Skip all DISM health checks (CheckHealth, ScanHealth, RestoreHealth).

.PARAMETER SkipSFC
    Skip the SFC /scannow step.

.PARAMETER ExportTarget
    Export target after repair: USB or ISO. Activates the RepairAndExport
    parameter set.

.PARAMETER DiskNumber
    USB disk number for USB export. Use Get-Disk to identify the target.

.PARAMETER DriveLetter
    Target drive letter for USB export (e.g., "E:").

.PARAMETER OutputPath
    Output file path for ISO export.
    Default: $env:USERPROFILE\Desktop\WindowsBackup.iso

.PARAMETER Source
    Offline WIM/ESD source path for DISM RestoreHealth when Windows Update
    is unavailable.

.PARAMETER LimitAccess
    Prevent DISM from using Windows Update as a repair source. Use with -Source.

.PARAMETER LogDirectory
    Directory for transcript log files.
    Default: $env:TEMP\CheckAndFix

.PARAMETER ContinueOnError
    Continue the repair pipeline even if a step fails.

.EXAMPLE
    .\CheckAndFix.ps1
    Runs the full DISM + SFC repair pipeline.

.EXAMPLE
    .\CheckAndFix.ps1 -ExportTarget USB -DiskNumber 2 -DriveLetter "E:"
    Repairs the system and creates a bootable USB drive.

.EXAMPLE
    .\CheckAndFix.ps1 -ExportTarget ISO -OutputPath "D:\Backup.iso"
    Repairs the system and creates a bootable ISO image.

.EXAMPLE
    .\CheckAndFix.ps1 -WhatIf
    Previews all operations without executing them.
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'RepairOnly')]
param(
    [Parameter(ParameterSetName = 'RepairOnly')]
    [Parameter(ParameterSetName = 'RepairAndExport')]
    [switch]$SkipDISM,

    [Parameter(ParameterSetName = 'RepairOnly')]
    [Parameter(ParameterSetName = 'RepairAndExport')]
    [switch]$SkipSFC,

    [Parameter(ParameterSetName = 'RepairAndExport', Mandatory = $true)]
    [ValidateSet('USB', 'ISO')]
    [string]$ExportTarget,

    [Parameter(ParameterSetName = 'RepairAndExport')]
    [int]$DiskNumber,

    [Parameter(ParameterSetName = 'RepairAndExport')]
    [string]$DriveLetter,

    [Parameter(ParameterSetName = 'RepairOnly')]
    [Parameter(ParameterSetName = 'RepairAndExport')]
    [string]$Source,

    [Parameter(ParameterSetName = 'RepairOnly')]
    [Parameter(ParameterSetName = 'RepairAndExport')]
    [switch]$LimitAccess,

    [Parameter(ParameterSetName = 'RepairAndExport')]
    [string]$OutputPath,

    [Parameter()]
    [string]$LogDirectory = "$env:TEMP\CheckAndFix",

    [Parameter(ParameterSetName = 'RepairOnly')]
    [Parameter(ParameterSetName = 'RepairAndExport')]
    [switch]$ContinueOnError
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Ensure log directory exists and start transcript
# ---------------------------------------------------------------------------

if (-not (Test-Path -Path $LogDirectory -PathType Container)) {
    New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$transcriptPath = Join-Path -Path $LogDirectory -ChildPath "CheckAndFix_$timestamp.transcript.txt"

try {
    Start-Transcript -Path $transcriptPath -Append | Out-Null
}
catch {
    Write-Warning "Could not start transcript at '$transcriptPath': $_"
}

# ---------------------------------------------------------------------------
# Import the CheckAndFix module
# ---------------------------------------------------------------------------

try {
    $manifestPath = Join-Path -Path $PSScriptRoot -ChildPath 'CheckAndFix.psd1'
    Import-Module -Name $manifestPath -Force -ErrorAction Stop
    Write-Host '[CheckAndFix] Module loaded successfully.' -ForegroundColor Cyan
}
catch {
    Write-Host "[CheckAndFix] Failed to load module: $_" -ForegroundColor Red
    throw
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  CheckAndFix — Windows System Repair & Export Tool' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

$overallStartTime = Get-Date
$repairResult = $null
$exportResult = $null

# ---------------------------------------------------------------------------
# Phase 1: Repair Pipeline
# ---------------------------------------------------------------------------

try {
    Write-Host '[Phase 1] Running repair pipeline...' -ForegroundColor Cyan
    Write-Host ''

    $repairParams = @{}

    if ($SkipDISM) {
        $repairParams['SkipDISM'] = $true
    }
    if ($SkipSFC) {
        $repairParams['SkipSFC'] = $true
    }
    if ($ContinueOnError) {
        $repairParams['ContinueOnError'] = $true
    }
    if ($PSBoundParameters.ContainsKey('Source')) {
        $repairParams['Source'] = $Source
    }
    if ($LimitAccess) {
        $repairParams['LimitAccess'] = $true
    }
    if ($WhatIfPreference) {
        $repairParams['WhatIf'] = $true
    }

    $repairResult = Start-RepairPipeline @repairParams

    Write-Host ''
    if ($repairResult.OverallSuccess) {
        Write-Host '[Phase 1] Repair pipeline completed successfully.' -ForegroundColor Green
    }
    else {
        Write-Host '[Phase 1] Repair pipeline completed with failures.' -ForegroundColor Yellow
        if (-not $ContinueOnError -and $PSCmdlet.ParameterSetName -eq 'RepairAndExport') {
            Write-Host '[Phase 1] Skipping export due to repair failures. Use -ContinueOnError to proceed anyway.' -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "[Phase 1] Repair pipeline encountered an error: $_" -ForegroundColor Red
    $repairResult = [PSCustomObject]@{
        Steps          = @()
        OverallSuccess = $false
        StartTime      = $overallStartTime
        EndTime        = Get-Date
        Duration       = (Get-Date) - $overallStartTime
        Error          = $_.Exception.Message
    }
}

# ---------------------------------------------------------------------------
# Phase 2: Export Pipeline (RepairAndExport parameter set only)
# ---------------------------------------------------------------------------

if ($PSCmdlet.ParameterSetName -eq 'RepairAndExport') {
    $shouldExport = $true

    if ($null -ne $repairResult -and -not $repairResult.OverallSuccess -and -not $ContinueOnError) {
        $shouldExport = $false
    }

    if ($shouldExport) {
        try {
            Write-Host ''
            Write-Host "[Phase 2] Running export pipeline (target: $ExportTarget)..." -ForegroundColor Cyan
            Write-Host ''

            $exportParams = @{
                ExportTarget = $ExportTarget
            }

            if ($PSBoundParameters.ContainsKey('DiskNumber')) {
                $exportParams['DiskNumber'] = $DiskNumber
            }
            if ($PSBoundParameters.ContainsKey('DriveLetter')) {
                $exportParams['DriveLetter'] = $DriveLetter
            }
            if ($PSBoundParameters.ContainsKey('OutputPath')) {
                $exportParams['OutputPath'] = $OutputPath
            }
            if ($PSBoundParameters.ContainsKey('Source')) {
                $exportParams['SourcePath'] = $Source
            }
            if ($WhatIfPreference) {
                $exportParams['WhatIf'] = $true
            }

            $exportResult = Start-ExportPipeline @exportParams

            Write-Host ''
            if ($exportResult.Success) {
                Write-Host "[Phase 2] Export to $ExportTarget completed successfully." -ForegroundColor Green
            }
            else {
                Write-Host "[Phase 2] Export to $ExportTarget completed with failures." -ForegroundColor Yellow
            }
        }
        catch {
            Write-Host "[Phase 2] Export pipeline encountered an error: $_" -ForegroundColor Red
            $exportResult = [PSCustomObject]@{
                Success      = $false
                ExportTarget = $ExportTarget
                Error        = $_.Exception.Message
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

$overallEndTime = Get-Date
$overallDuration = $overallEndTime - $overallStartTime

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host '  Summary' -ForegroundColor Cyan
Write-Host '====================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host "  Start Time : $($overallStartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  End Time   : $($overallEndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host "  Duration   : $($overallDuration.ToString())"
Write-Host "  Log File   : $transcriptPath"
Write-Host ''

# Repair summary
if ($null -ne $repairResult) {
    if ($repairResult.OverallSuccess) {
        Write-Host '  Repair     : PASSED' -ForegroundColor Green
    }
    else {
        Write-Host '  Repair     : FAILED' -ForegroundColor Red
    }

    if ($repairResult.Steps -and $repairResult.Steps.Count -gt 0) {
        foreach ($step in $repairResult.Steps) {
            $stepStatus = 'FAIL'
            $stepColor = 'Red'
            if ($step.Result.Success) {
                $stepStatus = 'PASS'
                $stepColor = 'Green'
            }
            Write-Host "    - $($step.Name): $stepStatus" -ForegroundColor $stepColor
        }
    }
}

# Export summary
if ($null -ne $exportResult) {
    Write-Host ''
    if ($exportResult.Success) {
        Write-Host "  Export ($ExportTarget) : PASSED" -ForegroundColor Green
    }
    else {
        Write-Host "  Export ($ExportTarget) : FAILED" -ForegroundColor Red
    }
}

Write-Host ''
Write-Host '====================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Stop transcript
# ---------------------------------------------------------------------------

try {
    Stop-Transcript | Out-Null
}
catch {
    # Transcript may not be running if Start-Transcript failed earlier
}

# ---------------------------------------------------------------------------
# Return overall result
# ---------------------------------------------------------------------------

$overallSuccess = $true
if ($null -ne $repairResult -and -not $repairResult.OverallSuccess) {
    $overallSuccess = $false
}
if ($null -ne $exportResult -and -not $exportResult.Success) {
    $overallSuccess = $false
}

[PSCustomObject]@{
    OverallSuccess = $overallSuccess
    RepairResult   = $repairResult
    ExportResult   = $exportResult
    StartTime      = $overallStartTime
    EndTime        = $overallEndTime
    Duration       = $overallDuration
    TranscriptPath = $transcriptPath
}
