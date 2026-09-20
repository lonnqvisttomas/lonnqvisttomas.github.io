#Requires -Version 5.1

# Set-StartMenuConfig.Tests.ps1 — Pester 5.x tests for Set-StartMenuConfig.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Set-StartMenuConfig.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Set-StartMenuConfig'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Set-StartMenuConfig
# ============================================================================

Describe 'Set-StartMenuConfig' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Set-StartMenuConfig'
    }

    Context 'Sets Start_Layout registry value' {

        It 'Sets Start_Layout to 1 for more pins layout' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Start_Layout' -and $Value -eq 1
                }
            }
        }

        It 'Writes Start_Layout to the Explorer Advanced path' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Start_Layout' -and
                    $Path -eq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
                }
            }
        }
    }

    Context 'Sets VisiblePlaces binary value' {

        It 'Writes a 32-byte VisiblePlaces binary blob' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'VisiblePlaces' -and $Value.Length -eq 32
                }
            }
        }

        It 'Writes VisiblePlaces to the Start path' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'VisiblePlaces' -and
                    $Path -eq 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start'
                }
            }
        }

        It 'VisiblePlaces binary starts with the first GUID bytes' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'VisiblePlaces' -and
                    $Value[0] -eq 0x52 -and
                    $Value[1] -eq 0x73 -and
                    $Value[2] -eq 0x08 -and
                    $Value[3] -eq 0x86
                }
            }
        }
    }

    Context 'WhatIf support' {

        It 'Does not call Set-ItemProperty under WhatIf' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock New-Item {}

                $result = Set-StartMenuConfig -WhatIf

                Should -Not -Invoke Set-ItemProperty -ModuleName 'Set-StartMenuConfig'
                $result.Success | Should -BeTrue
            }
        }

        It 'Returns Success true under WhatIf' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock New-Item {}

                $result = Set-StartMenuConfig -WhatIf

                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'Returns correct result structure' {

        It 'Returns an object with Success, Changes, and Warnings properties' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-StartMenuConfig -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'Changes'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
            }
        }

        It 'Records 2 changes for Start_Layout and VisiblePlaces' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-StartMenuConfig -Confirm:$false

                $result.Changes.Count | Should -Be 2
            }
        }

        It 'Changes array describes the Start_Layout and VisiblePlaces modifications' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-StartMenuConfig -Confirm:$false

                $changesText = $result.Changes -join ' '
                $changesText | Should -BeLike '*Start_Layout*'
                $changesText | Should -BeLike '*VisiblePlaces*'
            }
        }

        It 'Success is true when all settings are applied' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-StartMenuConfig -Confirm:$false

                $result.Success | Should -BeTrue
            }
        }

        It 'Warnings array is empty on success' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-StartMenuConfig -Confirm:$false

                $result.Warnings.Count | Should -Be 0
            }
        }
    }

    Context 'Registry key creation' {

        It 'Creates registry keys via New-Item when paths do not exist' {
            InModuleScope 'Set-StartMenuConfig' {
                Mock Test-Path { return $false }
                Mock New-Item {}
                Mock Set-ItemProperty {}

                Set-StartMenuConfig -Confirm:$false

                Should -Invoke New-Item -ModuleName 'Set-StartMenuConfig' -Times 1 -Scope It
            }
        }
    }
}
