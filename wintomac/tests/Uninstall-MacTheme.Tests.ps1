#Requires -Version 5.1

# Uninstall-MacTheme.Tests.ps1 — Pester 5.x tests for the Uninstall-MacTheme.ps1 entry-point script

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    $script:UninstallScript = Join-Path -Path $PSScriptRoot -ChildPath '..\Uninstall-MacTheme.ps1'

    # Track the expected backup paths for assertions
    $script:backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
    $script:backupPath = Join-Path -Path $script:backupDir -ChildPath 'backup.json'

    # Define stub functions so they can be mocked (Import-Module is mocked to prevent real loading)
    function Restore-OriginalSettings { }
}

AfterAll {
    # Clean up any backup file created during tests
    if (Test-Path -Path $script:backupPath) {
        Remove-Item -Path $script:backupPath -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Missing backup test
# ============================================================================

Describe 'Uninstall-MacTheme missing backup' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
    }

    It 'Throws when backup.json does NOT exist' {
        Mock Test-Path {
            if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                return $false
            }
            return $true
        }

        { & $script:UninstallScript -NoRestart -Confirm:$false } |
            Should -Throw '*Backup not found*'
    }
}

# ============================================================================
# Successful uninstall
# ============================================================================

Describe 'Uninstall-MacTheme successful restore' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path {
            if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                return $true
            }
            return $true
        }
        Mock Restore-OriginalSettings {
            [PSCustomObject]@{ Success = $true; RestoredKeys = 25; Warnings = @() }
        }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
        Mock Remove-Item {}
    }

    It 'Calls Restore-OriginalSettings' {
        & $script:UninstallScript -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Restore-OriginalSettings -Times 1
    }

    It 'Removes the AppData backup directory on success when not in WhatIf mode' {
        & $script:UninstallScript -NoRestart -Confirm:$false

        Should -Invoke Remove-Item -Times 1 -ParameterFilter {
            $Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac')
        }
    }

    It 'OverallSuccess is true when restore succeeds' {
        $result = & $script:UninstallScript -NoRestart -Confirm:$false -WhatIf

        $result.OverallSuccess | Should -BeTrue
    }
}

# ============================================================================
# Failed restore — backup preserved
# ============================================================================

Describe 'Uninstall-MacTheme failed restore' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path {
            if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                return $true
            }
            return $true
        }
        Mock Restore-OriginalSettings {
            [PSCustomObject]@{ Success = $false; Error = 'Restore failed' }
        }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
        Mock Remove-Item {}
    }

    It 'Does NOT remove the backup directory when restore fails' {
        & $script:UninstallScript -NoRestart -Confirm:$false

        Should -Invoke Remove-Item -Times 0
    }

    It 'OverallSuccess is false when restore fails' {
        $result = & $script:UninstallScript -NoRestart -Confirm:$false

        $result.OverallSuccess | Should -BeFalse
    }
}

# ============================================================================
# WhatIf tests
# ============================================================================

Describe 'Uninstall-MacTheme WhatIf mode' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path {
            if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                return $true
            }
            return $true
        }
        Mock Restore-OriginalSettings {
            [PSCustomObject]@{ Success = $true; RestoredKeys = 25; Warnings = @() }
        }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
        Mock Remove-Item {}
    }

    It 'Explorer restart does NOT happen in WhatIf mode' {
        & $script:UninstallScript -Confirm:$false -WhatIf

        Should -Invoke Stop-Process -Times 0
        Should -Invoke Start-Process -Times 0
    }

    It 'Cleanup does NOT remove directory in WhatIf mode' {
        & $script:UninstallScript -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Remove-Item -Times 0
    }
}

# ============================================================================
# Result structure test
# ============================================================================

Describe 'Uninstall-MacTheme result structure' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path {
            if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                return $true
            }
            return $true
        }
        Mock Restore-OriginalSettings {
            [PSCustomObject]@{ Success = $true; RestoredKeys = 25; Warnings = @() }
        }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
        Mock Remove-Item {}
    }

    It 'Returns PSCustomObject with OverallSuccess, RestoreResult, CleanedUp' {
        $result = & $script:UninstallScript -NoRestart -Confirm:$false -WhatIf

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallSuccess'
        $result.PSObject.Properties.Name | Should -Contain 'RestoreResult'
        $result.PSObject.Properties.Name | Should -Contain 'CleanedUp'
    }

    It 'Returns StartTime, EndTime, Duration in result' {
        $result = & $script:UninstallScript -NoRestart -Confirm:$false -WhatIf

        $result.PSObject.Properties.Name | Should -Contain 'StartTime'
        $result.PSObject.Properties.Name | Should -Contain 'EndTime'
        $result.PSObject.Properties.Name | Should -Contain 'Duration'
    }
}
