#Requires -Version 5.1

# Set-CursorScheme.Tests.ps1 — Pester 5.x tests for Set-CursorScheme.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Set-CursorScheme.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Set-CursorScheme'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Set-CursorScheme
# ============================================================================

Describe 'Set-CursorScheme' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Set-CursorScheme'
    }

    Context 'Successful cursor deployment and registration' {

        It 'Copies cursor files to the deployment directory' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur'   -FullName 'C:\assets\cursors\arrow.cur'),
                    (New-MockFileInfo -Name 'hand.cur'    -FullName 'C:\assets\cursors\hand.cur'),
                    (New-MockFileInfo -Name 'ibeam.cur'   -FullName 'C:\assets\cursors\ibeam.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}
                # Do NOT mock Add-Type — let the real CursorApi P/Invoke
                # type load so [CursorApi] resolves at runtime.

                $result = Set-CursorScheme -Confirm:$false

                Should -Invoke Copy-Item -Times 3
            }
        }

        It 'Sets the cursor scheme name to WinToMac' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                Set-CursorScheme -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq '(Default)' -and $Value -eq 'WinToMac'
                }
            }
        }

        It 'Returns Success true with Changes and CursorPath' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-CursorScheme -Confirm:$false

                $result.Success | Should -BeTrue
                $result.PSObject.Properties.Name | Should -Contain 'Changes'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
                $result.PSObject.Properties.Name | Should -Contain 'CursorPath'
                $result.CursorPath | Should -Not -BeNullOrEmpty
            }
        }
    }

    Context 'Graceful skip when no cursor assets exist' {

        It 'Returns Success true with a warning when no cursor files are found' {
            InModuleScope 'Set-CursorScheme' {
                Mock Test-Path { return $true }
                Mock Get-ChildItem { return @() }
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-CursorScheme -Confirm:$false

                $result.Success | Should -BeTrue
                $result.CursorPath | Should -BeNullOrEmpty
                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings[0] | Should -BeLike '*No cursor files*'
            }
        }

        It 'Returns Success true when assets directory does not exist' {
            InModuleScope 'Set-CursorScheme' {
                Mock Test-Path { return $false }
                Mock Get-ChildItem { return @() }

                $result = Set-CursorScheme -Confirm:$false

                $result.Success | Should -BeTrue
                $result.CursorPath | Should -BeNullOrEmpty
                $result.Changes.Count | Should -Be 0
            }
        }

        It 'Does not call Copy-Item when no cursor files are found' {
            InModuleScope 'Set-CursorScheme' {
                Mock Test-Path { return $true }
                Mock Get-ChildItem { return @() }
                Mock Copy-Item {}

                Set-CursorScheme -Confirm:$false

                Should -Not -Invoke Copy-Item
            }
        }
    }

    Context 'Cursor mapping by filename convention' {

        It 'Maps arrow.cur to the Arrow cursor type via Set-ItemProperty' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                Set-CursorScheme -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Arrow' -and $Type -eq 'ExpandString'
                }
            }
        }

        It 'Maps hand.cur to the Hand cursor type' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'hand.cur' -FullName 'C:\assets\cursors\hand.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                Set-CursorScheme -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Hand' -and $Type -eq 'ExpandString'
                }
            }
        }

        It 'Produces a warning when no cursor files match standard type names' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'unknown_cursor.cur' -FullName 'C:\assets\cursors\unknown_cursor.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-CursorScheme -Confirm:$false

                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings | Should -Contain 'No cursor files matched any standard cursor type names. Cursor types are unchanged.'
            }
        }
    }

    Context 'HKLM fallback to HKCU' {

        It 'Handles HKLM access denied gracefully and adds a warning' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )

                Mock Test-Path {
                    if ($Path -like 'HKLM:*') {
                        return $false
                    }
                    return $true
                }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {
                    if ($Path -like 'HKLM:*') {
                        throw 'Access denied'
                    }
                }
                Mock Copy-Item {}
                Mock Set-ItemProperty {
                    if ($Path -like 'HKLM:*') {
                        throw 'Access denied'
                    }
                }

                $result = Set-CursorScheme -Confirm:$false

                $result.Success | Should -BeTrue
                $result.Warnings | Should -Not -BeNullOrEmpty
                ($result.Warnings -join ' ') | Should -BeLike '*HKLM*'
            }
        }
    }

    Context 'Deployment directory creation' {

        It 'Creates the cursor deployment directory when it does not exist' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )
                $deployDir = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'WinToMac\cursors'

                Mock Test-Path {
                    # Only the deploy directory does not exist
                    if ($Path -eq $deployDir) {
                        return $false
                    }
                    return $true
                }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                Set-CursorScheme -Confirm:$false

                Should -Invoke New-Item -Times 1 -ParameterFilter {
                    $ItemType -eq 'Directory'
                }
            }
        }
    }

    Context 'WhatIf support' {

        It 'Does not copy files or set registry values under WhatIf' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur' -FullName 'C:\assets\cursors\arrow.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-CursorScheme -WhatIf

                Should -Not -Invoke Copy-Item -ModuleName 'Set-CursorScheme'
                Should -Not -Invoke Set-ItemProperty -ModuleName 'Set-CursorScheme'
                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'Multiple cursor types mapped' {

        It 'Maps all matching cursor files to their respective types' {
            InModuleScope 'Set-CursorScheme' {
                $mockFiles = @(
                    (New-MockFileInfo -Name 'arrow.cur'      -FullName 'C:\assets\cursors\arrow.cur'),
                    (New-MockFileInfo -Name 'help.ani'       -FullName 'C:\assets\cursors\help.ani'),
                    (New-MockFileInfo -Name 'wait.ani'       -FullName 'C:\assets\cursors\wait.ani'),
                    (New-MockFileInfo -Name 'crosshair.cur'  -FullName 'C:\assets\cursors\crosshair.cur'),
                    (New-MockFileInfo -Name 'hand.cur'       -FullName 'C:\assets\cursors\hand.cur')
                )

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFiles }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-CursorScheme -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Arrow' -and $Type -eq 'ExpandString'
                }
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Help' -and $Type -eq 'ExpandString'
                }
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Wait' -and $Type -eq 'ExpandString'
                }
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Crosshair' -and $Type -eq 'ExpandString'
                }
                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'Hand' -and $Type -eq 'ExpandString'
                }
            }
        }
    }
}
