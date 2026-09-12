#Requires -Version 5.1

function global:New-MockCommandResult {
    param(
        [int]$ExitCode = 0,
        [bool]$Success = $true,
        [string]$Output = 'mock output',
        [string]$Command = 'mock',
        [timespan]$Duration = [TimeSpan]::Zero
    )

    return [PSCustomObject]@{
        ExitCode = $ExitCode
        Success  = $Success
        Output   = $Output
        Command  = $Command
        Duration = $Duration
    }
}
