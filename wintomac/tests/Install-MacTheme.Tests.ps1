#Requires -Version 5.1

# Install-MacTheme.Tests.ps1 — Pester 5.x tests for the Install-MacTheme.ps1 entry-point script

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    $script:InstallScript = Join-Path -Path $PSScriptRoot -ChildPath '..\Install-MacTheme.ps1'

    # Ensure the WinToMac AppData directory exists for backup-path tests
    $script:backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
    $script:backupPath = Join-Path -Path $script:backupDir -ChildPath 'backup.json'

    # Define stub functions so they can be mocked (Import-Module is mocked to prevent real loading)
    function Backup-CurrentSettings { }
    function Restore-OriginalSettings { }
    function Set-TaskbarConfig { }
    function Set-VisualStyle { }
    function Set-Wallpaper { }
    function Set-CursorScheme { }
    function Set-StartMenuConfig { }
}

AfterAll {
    # Clean up any backup file created during tests
    if (Test-Path -Path $script:backupPath) {
        Remove-Item -Path $script:backupPath -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Idempotency tests
# ============================================================================

Describe 'Install-MacTheme idempotency' {

    BeforeEach {
        # Suppress console output
        Mock Write-Host {}

        # Prevent actual module loading
        Mock Import-Module {}

        # Mock all Set-* module functions to return success results
        Mock Backup-CurrentSettings {
            [PSCustomObject]@{ Success = $true; Skipped = $false; Message = 'Backup created' }
        }
        Mock Set-TaskbarConfig   { [PSCustomObject]@{ Success = $true } }
        Mock Set-VisualStyle     { [PSCustomObject]@{ Success = $true } }
        Mock Set-Wallpaper       { [PSCustomObject]@{ Success = $true } }
        Mock Set-CursorScheme    { [PSCustomObject]@{ Success = $true } }
        Mock Set-StartMenuConfig { [PSCustomObject]@{ Success = $true } }

        # Mock Explorer restart commands
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    Context 'When backup.json already exists' {

        BeforeEach {
            # Simulate backup file existing at the expected path
            Mock Test-Path {
                if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                    return $true
                }
                return $true
            }
        }

        It 'Does NOT call Backup-CurrentSettings (backup preserved)' {
            & $script:InstallScript -NoRestart -Confirm:$false -WhatIf

            Should -Invoke Backup-CurrentSettings -Times 0
        }

        It 'Still calls all Set-* modules (theme re-applied)' {
            & $script:InstallScript -NoRestart -Confirm:$false -WhatIf

            Should -Invoke Set-TaskbarConfig -Times 1
            Should -Invoke Set-VisualStyle -Times 1
            Should -Invoke Set-Wallpaper -Times 1
            Should -Invoke Set-CursorScheme -Times 1
            Should -Invoke Set-StartMenuConfig -Times 1
        }
    }

    Context 'When backup.json does NOT exist' {

        BeforeEach {
            Mock Test-Path {
                if ($Path -eq (Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json')) {
                    return $false
                }
                return $true
            }
        }

        It 'Calls Backup-CurrentSettings to create a backup' {
            & $script:InstallScript -NoRestart -Confirm:$false -WhatIf

            Should -Invoke Backup-CurrentSettings -Times 1
        }
    }
}

# ============================================================================
# Skip switch tests
# ============================================================================

Describe 'Install-MacTheme skip switches' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path { return $false }
        Mock Backup-CurrentSettings {
            [PSCustomObject]@{ Success = $true; Skipped = $false; Message = 'Backup created' }
        }
        Mock Set-TaskbarConfig   { [PSCustomObject]@{ Success = $true } }
        Mock Set-VisualStyle     { [PSCustomObject]@{ Success = $true } }
        Mock Set-Wallpaper       { [PSCustomObject]@{ Success = $true } }
        Mock Set-CursorScheme    { [PSCustomObject]@{ Success = $true } }
        Mock Set-StartMenuConfig { [PSCustomObject]@{ Success = $true } }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    It '-SkipDock prevents Set-TaskbarConfig from being called' {
        & $script:InstallScript -SkipDock -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Set-TaskbarConfig -Times 0
    }

    It '-SkipVisualStyle prevents Set-VisualStyle from being called' {
        & $script:InstallScript -SkipVisualStyle -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Set-VisualStyle -Times 0
    }

    It '-SkipWallpaper prevents Set-Wallpaper from being called' {
        & $script:InstallScript -SkipWallpaper -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Set-Wallpaper -Times 0
    }

    It '-SkipCursors prevents Set-CursorScheme from being called' {
        & $script:InstallScript -SkipCursors -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Set-CursorScheme -Times 0
    }

    It '-SkipStartMenu prevents Set-StartMenuConfig from being called' {
        & $script:InstallScript -SkipStartMenu -NoRestart -Confirm:$false -WhatIf

        Should -Invoke Set-StartMenuConfig -Times 0
    }
}

# ============================================================================
# WhatIf test
# ============================================================================

Describe 'Install-MacTheme WhatIf mode' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path { return $false }
        Mock Backup-CurrentSettings {
            [PSCustomObject]@{ Success = $true; Skipped = $false; Message = 'Backup created' }
        }
        Mock Set-TaskbarConfig   { [PSCustomObject]@{ Success = $true } }
        Mock Set-VisualStyle     { [PSCustomObject]@{ Success = $true } }
        Mock Set-Wallpaper       { [PSCustomObject]@{ Success = $true } }
        Mock Set-CursorScheme    { [PSCustomObject]@{ Success = $true } }
        Mock Set-StartMenuConfig { [PSCustomObject]@{ Success = $true } }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    It 'Explorer restart does NOT happen in WhatIf mode' {
        & $script:InstallScript -Confirm:$false -WhatIf

        Should -Invoke Stop-Process -Times 0
        Should -Invoke Start-Process -Times 0
    }
}

# ============================================================================
# Parameter validation tests
# ============================================================================

Describe 'Install-MacTheme parameter validation' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Backup-CurrentSettings {
            [PSCustomObject]@{ Success = $true; Skipped = $false; Message = 'Backup created' }
        }
        Mock Set-TaskbarConfig   { [PSCustomObject]@{ Success = $true } }
        Mock Set-VisualStyle     { [PSCustomObject]@{ Success = $true } }
        Mock Set-Wallpaper       { [PSCustomObject]@{ Success = $true } }
        Mock Set-CursorScheme    { [PSCustomObject]@{ Success = $true } }
        Mock Set-StartMenuConfig { [PSCustomObject]@{ Success = $true } }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    It 'Throws when -ConfigPath points to a nonexistent file' {
        Mock Test-Path {
            if ($Path -like '*nonexistent.json*') {
                return $false
            }
            return $false
        }

        { & $script:InstallScript -ConfigPath 'nonexistent.json' -NoRestart -Confirm:$false } |
            Should -Throw '*Configuration file not found*'
    }

    It 'Throws when -ConfigPath has invalid JSON content' {
        $tempFile = Join-Path -Path $env:TEMP -ChildPath 'wintomac_invalid_config.json'
        try {
            'this is { not valid json !!!' | Set-Content -Path $tempFile -Encoding UTF8

            Mock Test-Path {
                if ($Path -like 'HKCU:*' -or $Path -like 'HKLM:*') {
                    return $false
                }
                if ($LiteralPath) {
                    return $true
                }
                return $true
            }

            { & $script:InstallScript -ConfigPath $tempFile -NoRestart -Confirm:$false } |
                Should -Throw
        }
        finally {
            if (Test-Path -LiteralPath $tempFile) {
                Remove-Item -LiteralPath $tempFile -Force
            }
        }
    }
}

# ============================================================================
# Result structure test
# ============================================================================

Describe 'Install-MacTheme result structure' {

    BeforeEach {
        Mock Write-Host {}
        Mock Import-Module {}
        Mock Test-Path { return $false }
        Mock Backup-CurrentSettings {
            [PSCustomObject]@{ Success = $true; Skipped = $false; Message = 'Backup created' }
        }
        Mock Set-TaskbarConfig   { [PSCustomObject]@{ Success = $true } }
        Mock Set-VisualStyle     { [PSCustomObject]@{ Success = $true } }
        Mock Set-Wallpaper       { [PSCustomObject]@{ Success = $true } }
        Mock Set-CursorScheme    { [PSCustomObject]@{ Success = $true } }
        Mock Set-StartMenuConfig { [PSCustomObject]@{ Success = $true } }
        Mock Stop-Process {}
        Mock Start-Process {}
        Mock Start-Sleep {}
    }

    It 'Returns PSCustomObject with OverallSuccess, Steps, StartTime, EndTime, Duration' {
        $result = & $script:InstallScript -NoRestart -Confirm:$false -WhatIf

        $result | Should -Not -BeNullOrEmpty
        $result.PSObject.Properties.Name | Should -Contain 'OverallSuccess'
        $result.PSObject.Properties.Name | Should -Contain 'Steps'
        $result.PSObject.Properties.Name | Should -Contain 'StartTime'
        $result.PSObject.Properties.Name | Should -Contain 'EndTime'
        $result.PSObject.Properties.Name | Should -Contain 'Duration'
    }

    It 'OverallSuccess is true when all steps succeed' {
        $result = & $script:InstallScript -NoRestart -Confirm:$false -WhatIf

        $result.OverallSuccess | Should -BeTrue
    }
}
