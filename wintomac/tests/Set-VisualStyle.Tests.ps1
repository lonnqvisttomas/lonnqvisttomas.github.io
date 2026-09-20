#Requires -Version 5.1

# Set-VisualStyle.Tests.ps1 — Pester 5.x tests for Set-VisualStyle.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Set-VisualStyle.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Set-VisualStyle'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Set-VisualStyle
# ============================================================================

Describe 'Set-VisualStyle' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Set-VisualStyle'
    }

    Context 'Sets dark mode values' {

        It 'Sets AppsUseLightTheme to 0 for dark mode' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'AppsUseLightTheme' -and $Value -eq 0
                }
            }
        }

        It 'Sets SystemUsesLightTheme to 0 for system dark mode' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'SystemUsesLightTheme' -and $Value -eq 0
                }
            }
        }
    }

    Context 'Sets accent color' {

        It 'Sets AccentColorMenu to macOS blue (0xD47800)' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'AccentColorMenu' -and $Value -eq 0xD47800
                }
            }
        }

        It 'Sets ColorPrevalence to 1 to show accent on title bars' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'ColorPrevalence' -and $Value -eq 1
                }
            }
        }

        It 'Writes a 32-byte AccentPalette binary blob' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'AccentPalette' -and $Value.Length -eq 32
                }
            }
        }
    }

    Context 'Enables transparency' {

        It 'Sets EnableTransparency to 1' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'EnableTransparency' -and $Value -eq 1
                }
            }
        }
    }

    Context 'WhatIf support' {

        It 'Does not call Set-ItemProperty under WhatIf' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}
                Mock New-Item {}

                $result = Set-VisualStyle -WhatIf

                Should -Not -Invoke Set-ItemProperty -ModuleName 'Set-VisualStyle'
                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'Returns correct result' {

        It 'Returns an object with Success, Changes, and Warnings' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-VisualStyle -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'Changes'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
                $result.Success | Should -BeTrue
            }
        }

        It 'Records 6 changes for all visual style settings' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-VisualStyle -Confirm:$false

                $result.Changes.Count | Should -Be 6
            }
        }

        It 'Changes array mentions dark mode and accent color' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-VisualStyle -Confirm:$false

                $changesText = $result.Changes -join ' '
                $changesText | Should -BeLike '*dark mode*'
                $changesText | Should -BeLike '*AppsUseLightTheme*'
                $changesText | Should -BeLike '*AccentColorMenu*'
            }
        }

        It 'Warnings array is empty on success' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $true }
                Mock Set-ItemProperty {}

                $result = Set-VisualStyle -Confirm:$false

                $result.Warnings.Count | Should -Be 0
            }
        }
    }

    Context 'Registry key creation when path does not exist' {

        It 'Creates registry keys via New-Item when paths do not exist' {
            InModuleScope 'Set-VisualStyle' {
                Mock Test-Path { return $false }
                Mock New-Item {}
                Mock Set-ItemProperty {}

                Set-VisualStyle -Confirm:$false

                Should -Invoke New-Item -ModuleName 'Set-VisualStyle' -Times 1 -Scope It
            }
        }
    }
}
