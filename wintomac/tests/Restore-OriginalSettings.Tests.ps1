#Requires -Version 5.1

# Restore-OriginalSettings.Tests.ps1 — Pester 5.x tests for Restore-OriginalSettings.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')

    # Restore-OriginalSettings depends on Get-BackupKeyManifest from Backup-CurrentSettings
    $backupModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Backup-CurrentSettings.psm1'
    Import-Module -Name $backupModulePath -Force

    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Restore-OriginalSettings.psm1'
    Import-Module -Name $modulePath -Force

    # Ensure the backup directory exists so we can write test backup files.
    $script:backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
    if (-not (Test-Path -Path $script:backupDir)) {
        New-Item -Path $script:backupDir -ItemType Directory -Force | Out-Null
    }
    $script:backupPath = Join-Path -Path $script:backupDir -ChildPath 'backup.json'
}

AfterAll {
    # Clean up any test backup file
    if (Test-Path -Path $script:backupPath) {
        Remove-Item -Path $script:backupPath -Force -ErrorAction SilentlyContinue
    }

    $moduleName = 'Restore-OriginalSettings'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
    if (Get-Module -Name 'Backup-CurrentSettings') {
        Remove-Module -Name 'Backup-CurrentSettings' -Force
    }
}

# ============================================================================
# Write-RegistryValue (internal helper)
# ============================================================================

Describe 'Write-RegistryValue' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Restore-OriginalSettings'
    }

    Context 'Setting DWord values' {

        It 'Sets a DWord registry value and returns Success with Action Set' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestVal' -Value 42 -Type 'DWord'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Set'
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Type -eq 'DWord'
                }
            }
        }
    }

    Context 'Setting String values' {

        It 'Sets a String registry value' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestStr' -Value 'hello' -Type 'String'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Set'
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Type -eq 'String'
                }
            }
        }
    }

    Context 'Setting ExpandString values' {

        It 'Sets an ExpandString registry value' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestExpand' -Value '%SystemRoot%\test.cur' -Type 'ExpandString'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Set'
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Type -eq 'ExpandString'
                }
            }
        }
    }

    Context 'Null values trigger removal' {

        It 'Removes the property when value is null and property exists' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty { return [PSCustomObject]@{ TestVal = 'exists' } }
                Mock Remove-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestVal' -Value $null -Type 'DWord'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Remove'
                Should -Invoke Remove-ItemProperty -Times 1
            }
        }

        It 'Skips removal when value is null and property does not exist' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty { return $null }
                Mock Remove-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestVal' -Value $null -Type 'DWord'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Skip'
                Should -Not -Invoke Remove-ItemProperty
            }
        }

        It 'Skips removal when path does not exist and value is null' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $false }
                Mock Remove-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'TestVal' -Value $null -Type 'DWord'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Skip'
                Should -Not -Invoke Remove-ItemProperty
            }
        }
    }

    Context 'Binary values decoded from Base64' {

        It 'Decodes a hashtable with _type Binary and Value Base64 to bytes' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $binaryValue = @{ _type = 'Binary'; Value = 'AQIDBA==' }
                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'BinVal' -Value $binaryValue -Type 'Binary'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Set'
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Type -eq 'Binary'
                }
            }
        }

        It 'Decodes a raw Base64 string for Binary type' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'BinVal' -Value 'AQIDBA==' -Type 'Binary'

                $result.Success | Should -BeTrue
                $result.Action | Should -Be 'Set'
            }
        }
    }

    Context 'Missing parent key creation' {

        It 'Creates the parent key when path does not exist' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $false }
                Mock New-Item {}
                Mock Set-ItemProperty {}

                $result = Write-RegistryValue -Path 'HKCU:\Test\New' -ValueName 'Val' -Value 1 -Type 'DWord'

                $result.Success | Should -BeTrue
                Should -Invoke New-Item -Times 1
            }
        }
    }

    Context 'Error handling' {

        It 'Returns Success false with error message when Set-ItemProperty fails' {
            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty { throw 'Access denied' }

                $result = Write-RegistryValue -Path 'HKCU:\Test' -ValueName 'Val' -Value 1 -Type 'DWord'

                $result.Success | Should -BeFalse
                $result.Action | Should -BeLike 'Error:*'
            }
        }
    }
}

# ============================================================================
# Restore-OriginalSettings
# ============================================================================

Describe 'Restore-OriginalSettings' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Restore-OriginalSettings'
    }

    AfterEach {
        # Clean up the test backup file after each test
        $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
        if (Test-Path -LiteralPath $backupFile) {
            Remove-Item -LiteralPath $backupFile -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'Successful restore writes all values back' {

        It 'Returns a result with Success, RestoredKeys, and Warnings properties' {
            # Write a real backup file that the function can read via
            # [System.IO.File]::ReadAllText (cannot be mocked).
            $backupJson = New-MockBackupJson -AsJson
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, $backupJson, [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    # $Name arrives as String[] from the cmdlet parameter binding;
                    # coerce to scalar for Add-Member.
                    $propName = if ($Name -is [array]) { $Name[0] } else { [string]$Name }
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $propName -Value 'exists'
                    return $obj
                }
                Mock Set-ItemProperty {}
                Mock Remove-ItemProperty {}
                Mock New-Item {}

                $result = Restore-OriginalSettings -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'RestoredKeys'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            }
        }

        It 'Calls Set-ItemProperty for DWord entries in the backup' {
            $backupJson = New-MockBackupJson -AsJson
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, $backupJson, [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    # $Name arrives as String[] from the cmdlet parameter binding;
                    # coerce to scalar for Add-Member.
                    $propName = if ($Name -is [array]) { $Name[0] } else { [string]$Name }
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $propName -Value 'exists'
                    return $obj
                }
                Mock Set-ItemProperty {}
                Mock Remove-ItemProperty {}
                Mock New-Item {}

                $result = Restore-OriginalSettings -Confirm:$false

                Should -Invoke Set-ItemProperty -ModuleName 'Restore-OriginalSettings' -Times 1 -Scope It -ParameterFilter {
                    $Name -eq 'TaskbarAl'
                }
            }
        }
    }

    Context 'Missing backup file produces error' {

        It 'Returns Success false when backup file does not exist' {
            InModuleScope 'Restore-OriginalSettings' {
                # Test-Path for the backup file returns false; no real file exists
                # because AfterEach cleans up.
                Mock Test-Path {
                    if ($Path -like '*backup.json*') {
                        return $false
                    }
                    return $true
                }

                $result = Restore-OriginalSettings -Confirm:$false

                $result.Success | Should -BeFalse
                $result.RestoredKeys | Should -Be 0
                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings[0] | Should -BeLike '*Backup file not found*'
            }
        }
    }

    Context 'Invalid JSON produces error' {

        It 'Returns Success false when backup file contains invalid JSON' {
            # Write invalid JSON to the real file
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, 'not valid json {{{', [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }

                $result = Restore-OriginalSettings -Confirm:$false

                $result.Success | Should -BeFalse
                $result.Warnings.Count | Should -BeGreaterThan 0
            }
        }
    }

    Context 'WhatIf mode does not modify registry' {

        It 'Does not invoke Set-ItemProperty or Remove-ItemProperty under WhatIf' {
            $backupJson = New-MockBackupJson -AsJson
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, $backupJson, [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Remove-ItemProperty {}
                Mock New-Item {}

                $result = Restore-OriginalSettings -WhatIf

                Should -Not -Invoke Set-ItemProperty -ModuleName 'Restore-OriginalSettings'
                Should -Not -Invoke Remove-ItemProperty -ModuleName 'Restore-OriginalSettings'
            }
        }
    }

    Context 'Null values trigger Remove-ItemProperty' {

        It 'Calls Remove-ItemProperty for entries stored as null' {
            $backupJson = New-MockBackupJson -IncludeNullValues -AsJson
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, $backupJson, [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    # $Name arrives as String[] from the cmdlet parameter binding;
                    # coerce to scalar for Add-Member.
                    $propName = if ($Name -is [array]) { $Name[0] } else { [string]$Name }
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $propName -Value 'exists'
                    return $obj
                }
                Mock Set-ItemProperty {}
                Mock Remove-ItemProperty {}
                Mock New-Item {}

                $result = Restore-OriginalSettings -Confirm:$false

                # The IncludeNullValues flag sets (Default) and Arrow to null,
                # so Remove-ItemProperty should be called for them.
                # Use -Scope It (not -ModuleName) since the mock is scoped
                # inside InModuleScope already.
                Should -Invoke Remove-ItemProperty -Scope It
            }
        }
    }

    Context 'Result structure' {

        It 'Returns RestoredKeys greater than zero on successful restore' {
            $backupJson = New-MockBackupJson -AsJson
            $backupFile = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\backup.json'
            [System.IO.File]::WriteAllText($backupFile, $backupJson, [System.Text.Encoding]::UTF8)

            InModuleScope 'Restore-OriginalSettings' {
                Mock Test-Path { return $true }
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    # $Name arrives as String[] from the cmdlet parameter binding;
                    # coerce to scalar for Add-Member.
                    $propName = if ($Name -is [array]) { $Name[0] } else { [string]$Name }
                    $obj = [PSCustomObject]@{}
                    $obj | Add-Member -MemberType NoteProperty -Name $propName -Value 'exists'
                    return $obj
                }
                Mock Set-ItemProperty {}
                Mock Remove-ItemProperty {}
                Mock New-Item {}

                $result = Restore-OriginalSettings -Confirm:$false

                $result.RestoredKeys | Should -BeGreaterThan 0
            }
        }
    }
}

# ============================================================================
# Backup-Restore round-trip validation
# ============================================================================

Describe 'Backup-Restore round-trip' {
    BeforeAll {
        . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    }

    It 'DWord values survive JSON serialization round-trip' {
        InModuleScope 'Restore-OriginalSettings' {
            $backupDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac'
            $backupPath = Join-Path -Path $backupDir -ChildPath 'backup.json'

            $roundTripJson = New-MockBackupJson
            $jsonText = $roundTripJson | ConvertTo-Json -Depth 10

            Mock Test-Path { return $true }
            Mock Get-Content { return $jsonText }
            Mock Get-ItemProperty {
                $obj = [PSCustomObject]@{}
                $propName = if ($Name -is [array]) { $Name[0] } else { [string]$Name }
                $obj | Add-Member -MemberType NoteProperty -Name $propName -Value 'exists'
                return $obj
            }
            Mock Set-ItemProperty {}
            Mock Remove-ItemProperty {}
            Mock New-Item {}

            $result = Restore-OriginalSettings -Confirm:$false

            $result.Success | Should -Be $true
            $result.RestoredKeys | Should -BeGreaterThan 0
            Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                $Name -eq 'TaskbarAl' -and $Value -eq 0 -and $Type -eq 'DWord'
            }
        }
    }
}
