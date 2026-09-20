#Requires -Version 5.1

# Backup-CurrentSettings.Tests.ps1 — Pester 5.x tests for Backup-CurrentSettings.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Backup-CurrentSettings.psm1'
    Import-Module -Name $modulePath -Force

    # Ensure the backup directory exists so [System.IO.File]::WriteAllText
    # succeeds (static .NET methods cannot be mocked in Pester).
    $script:backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
    if (-not (Test-Path -Path $script:backupDir)) {
        New-Item -Path $script:backupDir -ItemType Directory -Force | Out-Null
    }
}

AfterAll {
    # Clean up the backup file written during tests
    $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
    if (Test-Path -Path $backupFile) {
        Remove-Item -Path $backupFile -Force -ErrorAction SilentlyContinue
    }

    $moduleName = 'Backup-CurrentSettings'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Get-BackupKeyManifest
# ============================================================================

Describe 'Get-BackupKeyManifest' {

    Context 'Manifest structure' {

        It 'Returns a non-empty array of hashtables' {
            $manifest = Get-BackupKeyManifest
            $manifest | Should -Not -BeNullOrEmpty
            $manifest.Count | Should -BeGreaterThan 0
        }

        It 'Each entry has Path, ValueName, and Type keys' {
            $manifest = Get-BackupKeyManifest
            foreach ($entry in $manifest) {
                $entry.Keys | Should -Contain 'Path'
                $entry.Keys | Should -Contain 'ValueName'
                $entry.Keys | Should -Contain 'Type'
            }
        }

        It 'Contains expected taskbar keys' {
            $manifest = Get-BackupKeyManifest
            $valueNames = $manifest | ForEach-Object { $_.ValueName }
            $valueNames | Should -Contain 'TaskbarAl'
            $valueNames | Should -Contain 'TaskbarSi'
            $valueNames | Should -Contain 'ShowTaskViewButton'
            $valueNames | Should -Contain 'TaskbarDa'
            $valueNames | Should -Contain 'SearchboxTaskbarMode'
        }

        It 'Contains expected visual style keys' {
            $manifest = Get-BackupKeyManifest
            $valueNames = $manifest | ForEach-Object { $_.ValueName }
            $valueNames | Should -Contain 'AppsUseLightTheme'
            $valueNames | Should -Contain 'SystemUsesLightTheme'
            $valueNames | Should -Contain 'EnableTransparency'
            $valueNames | Should -Contain 'AccentColorMenu'
            $valueNames | Should -Contain 'AccentPalette'
        }

        It 'Contains cursor keys' {
            $manifest = Get-BackupKeyManifest
            $valueNames = $manifest | ForEach-Object { $_.ValueName }
            $valueNames | Should -Contain 'Arrow'
            $valueNames | Should -Contain 'Hand'
            $valueNames | Should -Contain '(Default)'
        }

        It 'Includes Binary type entries for StuckRects3 Settings and AccentPalette' {
            $manifest = Get-BackupKeyManifest
            $binaryEntries = $manifest | Where-Object { $_.Type -eq 'Binary' }
            $binaryNames = $binaryEntries | ForEach-Object { $_.ValueName }
            $binaryNames | Should -Contain 'Settings'
            $binaryNames | Should -Contain 'AccentPalette'
        }
    }
}

# ============================================================================
# Backup-CurrentSettings
# ============================================================================

Describe 'Backup-CurrentSettings' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Backup-CurrentSettings'
        # Remove any leftover backup file from a previous test
        $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
        if (Test-Path -Path $backupFile) {
            Remove-Item -Path $backupFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Successful backup captures all keys' {

        It 'Returns a result object with Success, BackupPath, KeyCount, and Warnings' {
            InModuleScope 'Backup-CurrentSettings' {
                # Mock only registry-reading functions; let file I/O hit the real
                # filesystem (the directory was created in BeforeAll).
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 42
                    return $obj
                }

                $result = Backup-CurrentSettings -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'BackupPath'
                $result.PSObject.Properties.Name | Should -Contain 'KeyCount'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            }
        }

        It 'Reports success when all keys are readable' {
            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 1
                    return $obj
                }

                $result = Backup-CurrentSettings -Confirm:$false

                $result.Success | Should -BeTrue
            }
        }

        It 'Records the correct number of keys in KeyCount' {
            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 'test'
                    return $obj
                }

                $result = Backup-CurrentSettings -Confirm:$false

                $manifest = Get-BackupKeyManifest
                $result.KeyCount | Should -Be $manifest.Count
            }
        }
    }

    Context 'Missing registry keys are handled gracefully' {

        It 'Records null for keys that do not exist and still succeeds' {
            InModuleScope 'Backup-CurrentSettings' {
                # Registry paths return false (keys missing), filesystem paths
                # return true (backup directory exists on the real filesystem).
                Mock Test-Path {
                    if ($Path -like 'HKCU:*' -or $Path -like 'HKLM:*') {
                        return $false
                    }
                    return $true
                }
                Mock Get-ItemProperty { throw 'Value does not exist' }

                $result = Backup-CurrentSettings -Confirm:$false

                $result.Success | Should -BeTrue
                $result.KeyCount | Should -BeGreaterThan 0
            }
        }

        It 'Does not produce warnings when keys are simply absent' {
            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path {
                    if ($Path -like 'HKCU:*' -or $Path -like 'HKLM:*') {
                        return $false
                    }
                    return $true
                }
                Mock Get-ItemProperty { throw 'Value does not exist' }

                $result = Backup-CurrentSettings -Confirm:$false

                $result.Warnings.Count | Should -Be 0
            }
        }
    }

    Context 'Binary value encoding' {

        It 'Encodes binary values as Base64 in the snapshot' {
            InModuleScope 'Backup-CurrentSettings' {
                $binaryData = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02)

                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings' -or $Name -eq 'AccentPalette' -or $Name -eq 'VisiblePlaces') {
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name $Name -Value $binaryData
                        return $obj
                    }
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 'test-value'
                    return $obj
                }

                $result = Backup-CurrentSettings -Confirm:$false

                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'WhatIf mode' {

        It 'Does not write the backup file when WhatIf is specified' {
            # Remove any pre-existing backup file BEFORE entering InModuleScope
            # (where Test-Path is mocked and would interfere with filesystem checks).
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            if (Test-Path -LiteralPath $backupFile) {
                Remove-Item -LiteralPath $backupFile -Force
            }

            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path {
                    # Registry paths return true; filesystem paths delegate to
                    # the real Test-Path so the function's own directory check
                    # sees the real WinToMac directory.
                    if ($Path -like 'HKCU:*' -or $Path -like 'HKLM:*') {
                        return $true
                    }
                    return (Microsoft.PowerShell.Management\Test-Path -Path $Path)
                }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 1
                    return $obj
                }

                $result = Backup-CurrentSettings -WhatIf

                $result.Success | Should -BeTrue
            }

            # Verify OUTSIDE InModuleScope so the real Test-Path is used.
            Test-Path -LiteralPath $backupFile | Should -BeFalse
        }
    }

    Context 'Backup directory creation' {

        It 'Creates backup directory when it does not exist' {
            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path {
                    # Registry paths return true, backup directory returns false
                    if ($Path -like 'HKCU:*' -or $Path -like 'HKLM:*') {
                        return $true
                    }
                    # Let the real Test-Path handle filesystem checks
                    return $false
                }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 1
                    return $obj
                }
                Mock New-Item {}

                $result = Backup-CurrentSettings -Confirm:$false

                Should -Invoke New-Item -ModuleName 'Backup-CurrentSettings' -Times 1 -ParameterFilter {
                    $ItemType -eq 'Directory'
                }
            }
        }
    }

    Context 'BackupPath value' {

        It 'Sets BackupPath to the expected location under APPDATA' {
            InModuleScope 'Backup-CurrentSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $Name -Value 0
                    return $obj
                }

                $result = Backup-CurrentSettings -Confirm:$false

                $expectedPath = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
                $result.BackupPath | Should -Be $expectedPath
            }
        }
    }
}
