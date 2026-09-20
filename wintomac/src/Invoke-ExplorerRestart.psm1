# Invoke-ExplorerRestart.psm1 — Shared Explorer restart logic
#
# Used by both Install-MacTheme.ps1 and Uninstall-MacTheme.ps1 to prompt
# the user and restart explorer.exe after theme changes.
#
# Requires: PowerShell 5.1+

Set-StrictMode -Version Latest

function Invoke-ExplorerRestart {
    <#
    .SYNOPSIS
        Prompts to restart Explorer and performs the restart if confirmed.

    .DESCRIPTION
        Checks -NoRestart and -WhatIfPreference, prompts via ShouldContinue,
        then stops and restarts explorer.exe. The ShouldContinue call is
        guarded by an explicit WhatIfPreference check per the project
        instruction (ShouldContinue does not respect WhatIfPreference).

    .PARAMETER NoRestart
        When set, skips the restart entirely without prompting.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$NoRestart
    )

    if (-not $NoRestart -and -not $WhatIfPreference) {
        Write-Host ''
        if ($PSCmdlet.ShouldContinue('Restart Explorer to apply changes?', 'Explorer Restart')) {
            Write-Host '[Explorer] Restarting Explorer...' -ForegroundColor Cyan
            Stop-Process -Name explorer -Force
            Start-Sleep -Seconds 2
            Start-Process explorer.exe
            Write-Host '[Explorer] Explorer restarted.' -ForegroundColor Green
        }
        else {
            Write-Host '[Explorer] Explorer restart skipped. Changes will apply on next restart.' -ForegroundColor Yellow
        }
    }
}
