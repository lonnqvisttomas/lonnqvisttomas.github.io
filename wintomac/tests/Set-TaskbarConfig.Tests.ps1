#Requires -Version 5.1

# Set-TaskbarConfig.Tests.ps1 — Pester 5.x tests for Set-TaskbarConfig.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Set-TaskbarConfig.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Set-TaskbarConfig'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Set-TaskbarConfig
# ============================================================================

Describe 'Set-TaskbarConfig' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Set-TaskbarConfig'
        Mock Write-Warning {} -ModuleName 'Set-TaskbarConfig'
    }

    Context 'Sets all registry values correctly' {

        It 'Sets TaskbarAl to 1 for center alignment' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                    $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                    return $obj
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'TaskbarAl' -and $Value -eq 1
                }
            }
        }

        It 'Sets TaskbarSi to 0 for small taskbar size' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                    $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                    return $obj
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'TaskbarSi' -and $Value -eq 0
                }
            }
        }

        It 'Sets ShowTaskViewButton to 0' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                    $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                    return $obj
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'ShowTaskViewButton' -and $Value -eq 0
                }
            }
        }

        It 'Sets TaskbarDa to 0 to disable Widgets' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                    $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                    return $obj
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'TaskbarDa' -and $Value -eq 0
                }
            }
        }

        It 'Sets SearchboxTaskbarMode to 0 to hide search box' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    $obj = [PSCustomObject]@{}
                    $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                    $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                    return $obj
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'SearchboxTaskbarMode' -and $Value -eq 0
                }
            }
        }
    }

    Context 'StuckRects3 binary modification' {

        It 'Sets the auto-hide bit in StuckRects3 Settings byte 8' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings') {
                        $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                        return $obj
                    }
                    return $null
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Settings' -and $Type -eq 'Binary'
                }
            }
        }

        It 'Produces a warning when StuckRects3 key does not exist' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path {
                    if ($Path -like '*StuckRects3*') {
                        return $false
                    }
                    return $true
                }
                Mock Set-ItemProperty {}

                $result = Set-TaskbarConfig -Confirm:$false

                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings[0] | Should -BeLike '*StuckRects3*'
            }
        }

        It 'Produces a warning when StuckRects3 binary is too short' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings') {
                        $bytes = [byte[]](0x01, 0x02)
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                        return $obj
                    }
                    return $null
                }

                $result = Set-TaskbarConfig -Confirm:$false

                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings[0] | Should -BeLike '*too short*'
            }
        }
    }

    Context 'WhatIf mode makes no changes' {

        It 'Does not call Set-ItemProperty when WhatIf is specified' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock New-Item {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings') {
                        $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                        return $obj
                    }
                    return $null
                }

                $result = Set-TaskbarConfig -WhatIf

                Should -Not -Invoke Set-ItemProperty -ModuleName 'Set-TaskbarConfig'
                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'Returns correct result structure' {

        It 'Returns an object with Success, Changes, and Warnings properties' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings') {
                        $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                        return $obj
                    }
                    return $null
                }

                $result = Set-TaskbarConfig -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'Changes'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
                $result.Success | Should -BeTrue
                $result.Changes.Count | Should -BeGreaterOrEqual 5
            }
        }

        It 'Changes array describes each modification' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    if ($Name -eq 'Settings') {
                        $bytes = [byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)
                        $obj = [PSCustomObject]@{}
                        $obj | Add-Member -MemberType NoteProperty -Name 'Settings' -Value $bytes
                        return $obj
                    }
                    return $null
                }

                $result = Set-TaskbarConfig -Confirm:$false

                $changesText = $result.Changes -join ' '
                $changesText | Should -BeLike '*TaskbarAl*'
                $changesText | Should -BeLike '*TaskbarSi*'
                $changesText | Should -BeLike '*ShowTaskViewButton*'
                $changesText | Should -BeLike '*TaskbarDa*'
                $changesText | Should -BeLike '*SearchboxTaskbarMode*'
            }
        }
    }

    Context 'Registry key creation' {

        It 'Creates registry key when path does not exist' {
            InModuleScope 'Set-TaskbarConfig' {
                Mock Test-Path { return $false }
                Mock New-Item {}
                Mock Set-ItemProperty {}
                Mock Get-ItemProperty {
                    param($Path, $Name)
                    return $null
                }

                Set-TaskbarConfig -Confirm:$false

                Should -Invoke New-Item -ModuleName 'Set-TaskbarConfig' -Times 1 -Scope It
            }
        }
    }
}
