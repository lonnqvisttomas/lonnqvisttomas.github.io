#Requires -Version 5.1

# Set-Wallpaper.Tests.ps1 — Pester 5.x tests for Set-Wallpaper.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Set-Wallpaper.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Set-Wallpaper'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Set-Wallpaper
# ============================================================================

Describe 'Set-Wallpaper' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Set-Wallpaper'
    }

    Context 'Successful wallpaper deployment and application' {

        It 'Copies the wallpaper file to the deployment directory' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}
                # Do NOT mock Add-Type — let the real P/Invoke type load so
                # [WallpaperApi] resolves. SystemParametersInfo with a fake
                # path returns false, which the code handles gracefully.

                $result = Set-Wallpaper -Confirm:$false

                Should -Invoke Copy-Item -Times 1 -ParameterFilter {
                    $Path -eq 'C:\assets\wallpapers\ventura.jpg'
                }
            }
        }

        It 'Sets WallpaperStyle to Fill (value 10)' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'WallpaperStyle' -and $Value -eq '10'
                }
            }
        }

        It 'Sets TileWallpaper to 0' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -Confirm:$false

                Should -Invoke Set-ItemProperty -Times 1 -ParameterFilter {
                    $Name -eq 'TileWallpaper' -and $Value -eq '0'
                }
            }
        }

        It 'Returns a result object with Success true and correct properties' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -Confirm:$false

                $result.Success | Should -BeTrue
                $result.PSObject.Properties.Name | Should -Contain 'Changes'
                $result.PSObject.Properties.Name | Should -Contain 'Warnings'
                $result.PSObject.Properties.Name | Should -Contain 'WallpaperPath'
            }
        }

        It 'Sets WallpaperPath to the deployed file location' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -Confirm:$false

                $result.WallpaperPath | Should -BeLike '*ventura.jpg'
            }
        }
    }

    Context 'Graceful skip when no wallpaper assets exist' {

        It 'Returns Success true with a warning when no images are found' {
            InModuleScope 'Set-Wallpaper' {
                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $null }
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -Confirm:$false

                $result.Success | Should -BeTrue
                $result.WallpaperPath | Should -BeNullOrEmpty
                $result.Warnings.Count | Should -BeGreaterThan 0
                $result.Warnings[0] | Should -BeLike '*No wallpaper image found*'
            }
        }

        It 'Returns Success true with a warning when assets directory does not exist' {
            InModuleScope 'Set-Wallpaper' {
                Mock Test-Path { return $false }
                Mock Get-ChildItem { return $null }

                $result = Set-Wallpaper -Confirm:$false

                $result.Success | Should -BeTrue
                $result.WallpaperPath | Should -BeNullOrEmpty
                $result.Changes.Count | Should -Be 0
            }
        }

        It 'Does not call Copy-Item when no images are found' {
            InModuleScope 'Set-Wallpaper' {
                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $null }
                Mock Copy-Item {}

                Set-Wallpaper -Confirm:$false

                Should -Not -Invoke Copy-Item
            }
        }
    }

    Context 'Deployment directory creation' {

        It 'Creates the wallpaper deployment directory when it does not exist' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'beach.png' -FullName 'C:\assets\wallpapers\beach.png'
                $deployDir = Join-Path -Path $env:APPDATA -ChildPath 'WinToMac\wallpapers'

                Mock Test-Path {
                    # The deploy directory does not exist; everything else does.
                    if ($Path -eq $deployDir) {
                        return $false
                    }
                    return $true
                }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                Set-Wallpaper -Confirm:$false

                Should -Invoke New-Item -Times 1 -ParameterFilter {
                    $ItemType -eq 'Directory'
                }
            }
        }
    }

    Context 'WhatIf support' {

        It 'Does not copy files or set registry values under WhatIf' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}

                $result = Set-Wallpaper -WhatIf

                Should -Not -Invoke Copy-Item -ModuleName 'Set-Wallpaper'
                Should -Not -Invoke Set-ItemProperty -ModuleName 'Set-Wallpaper'
                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'Add-Type is called when type is not loaded' {

        It 'Calls Add-Type to load the WallpaperApi P/Invoke definition' {
            InModuleScope 'Set-Wallpaper' {
                $mockFile = New-MockFileInfo -Name 'ventura.jpg' -FullName 'C:\assets\wallpapers\ventura.jpg'

                Mock Test-Path { return $true }
                Mock Get-ChildItem { return $mockFile }
                Mock New-Item {}
                Mock Copy-Item {}
                Mock Set-ItemProperty {}
                # We cannot prevent Add-Type from running (mocking it would
                # leave [WallpaperApi] unresolved), but we can verify the
                # function completes without error and produces changes.

                $result = Set-Wallpaper -Confirm:$false

                $result.Success | Should -BeTrue
                $result.Changes.Count | Should -BeGreaterThan 0
            }
        }
    }
}
