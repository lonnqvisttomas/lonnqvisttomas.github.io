#Requires -Version 5.1

# Write-BootableMedia.Tests.ps1 — Pester 5.x tests for Write-BootableMedia.psm1

BeforeAll {
    # Import Repair-WindowsImage first since Write-BootableMedia depends on its functions
    $repairModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Repair-WindowsImage.psm1'
    Import-Module -Name $repairModulePath -Force

    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Write-BootableMedia.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    if (Get-Module -Name 'Write-BootableMedia') {
        Remove-Module -Name 'Write-BootableMedia' -Force
    }
    if (Get-Module -Name 'Repair-WindowsImage') {
        Remove-Module -Name 'Repair-WindowsImage' -Force
    }
}

# ============================================================================
# New-DiskpartScript
# ============================================================================

Describe 'New-DiskpartScript' {

    Context 'Script file creation' {

        It 'Creates a temp file with correct diskpart commands for given disk number' {
            InModuleScope 'Write-BootableMedia' {
                $scriptPath = New-DiskpartScript -DiskNumber 3 -DriveLetter 'E:'

                try {
                    $scriptPath | Should -Not -BeNullOrEmpty
                    (Test-Path -LiteralPath $scriptPath) | Should -BeTrue

                    $content = Get-Content -Path $scriptPath -Raw

                    $content | Should -Match 'select disk 3'
                    $content | Should -Match 'clean'
                    $content | Should -Match 'convert gpt'
                    $content | Should -Match 'create partition primary'
                    $content | Should -Match 'format'
                    $content | Should -Match 'assign letter=E'
                }
                finally {
                    if (Test-Path -LiteralPath $scriptPath) {
                        Remove-Item -LiteralPath $scriptPath -Force
                    }
                }
            }
        }

        It 'Uses the correct disk number in the select command' {
            InModuleScope 'Write-BootableMedia' {
                $scriptPath = New-DiskpartScript -DiskNumber 7 -DriveLetter 'F:'

                try {
                    $content = Get-Content -Path $scriptPath -Raw
                    $content | Should -Match 'select disk 7'
                }
                finally {
                    if (Test-Path -LiteralPath $scriptPath) {
                        Remove-Item -LiteralPath $scriptPath -Force
                    }
                }
            }
        }

        It 'Returns the full path to the generated script file' {
            InModuleScope 'Write-BootableMedia' {
                $scriptPath = New-DiskpartScript -DiskNumber 1 -DriveLetter 'G:'

                try {
                    $scriptPath | Should -BeOfType [string]
                    [System.IO.Path]::IsPathRooted($scriptPath) | Should -BeTrue
                }
                finally {
                    if (Test-Path -LiteralPath $scriptPath) {
                        Remove-Item -LiteralPath $scriptPath -Force
                    }
                }
            }
        }
    }
}

# ============================================================================
# Invoke-Diskpart
# ============================================================================

Describe 'Invoke-Diskpart' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
    }

    Context 'Invocation and cleanup' {

        It 'Calls Invoke-ExternalCommand with diskpart and /s arguments' {
            InModuleScope 'Write-BootableMedia' {
                # Create a real temp file so the ValidateScript passes
                $tempScript = [System.IO.Path]::GetTempFileName()

                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = "diskpart /s $tempScript"; Duration = [TimeSpan]::Zero
                    }
                }

                # Mock Remove-Item to prevent actual cleanup during test
                Mock Remove-Item {}
                Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -eq $tempScript }

                $result = Invoke-Diskpart -ScriptPath $tempScript -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $FilePath -eq 'diskpart' -and
                    $ArgumentList[0] -eq '/s' -and
                    $ArgumentList[1] -eq $tempScript
                }

                $result.Success | Should -BeTrue
            }
        }

        It 'Cleans up script file in finally block' {
            InModuleScope 'Write-BootableMedia' {
                # Create a real temp file
                $tempScript = [System.IO.Path]::GetTempFileName()
                'select disk 0' | Out-File -FilePath $tempScript -Encoding ASCII

                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Invoke-Diskpart -ScriptPath $tempScript -Confirm:$false

                # The finally block should have removed the temp file
                (Test-Path -LiteralPath $tempScript) | Should -BeFalse
            }
        }
    }
}

# ============================================================================
# Copy-InstallationFiles
# ============================================================================

Describe 'Copy-InstallationFiles' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
    }

    Context 'Robocopy invocation' {

        It 'Calls Invoke-ExternalCommand with robocopy and correct arguments' {
            InModuleScope 'Write-BootableMedia' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Copy-InstallationFiles -SourcePath 'C:\Source' -DestinationPath 'E:\' -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $FilePath -eq 'robocopy' -and
                    $ArgumentList -contains 'C:\Source' -and
                    $ArgumentList -contains 'E:\' -and
                    $ArgumentList -contains '/E' -and
                    $ArgumentList -contains '/MIR' -and
                    $ArgumentList -contains '/R:3' -and
                    $ArgumentList -contains '/W:5'
                }

                $result.Success | Should -BeTrue
            }
        }

        It 'Uses a SuccessPredicate where exit codes 0-7 are success and 8+ are failure' {
            InModuleScope 'Write-BootableMedia' {
                # Capture the SuccessPredicate via a global variable to cross scope boundaries
                $global:_testCapturedPredicate = $null
                Mock Invoke-ExternalCommand {
                    $global:_testCapturedPredicate = $SuccessPredicate
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Copy-InstallationFiles -SourcePath 'C:\Source' -DestinationPath 'E:\' -Confirm:$false

                try {
                    $global:_testCapturedPredicate | Should -Not -BeNullOrEmpty

                    # Verify the predicate considers 0-7 as success
                    (& $global:_testCapturedPredicate 0) | Should -BeTrue
                    (& $global:_testCapturedPredicate 1) | Should -BeTrue
                    (& $global:_testCapturedPredicate 7) | Should -BeTrue

                    # Verify the predicate considers 8+ as failure
                    (& $global:_testCapturedPredicate 8) | Should -BeFalse
                    (& $global:_testCapturedPredicate 16) | Should -BeFalse
                } finally {
                    Remove-Variable -Name '_testCapturedPredicate' -Scope Global -ErrorAction SilentlyContinue
                }
            }
        }
    }
}

# ============================================================================
# Set-BootConfiguration
# ============================================================================

Describe 'Set-BootConfiguration' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
    }

    Context 'Bcdboot invocation' {

        It 'Calls Invoke-ExternalCommand with bcdboot and correct arguments' {
            InModuleScope 'Write-BootableMedia' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $expectedWindowsPath = Join-Path -Path 'C:\' -ChildPath 'Windows'
                $result = Set-BootConfiguration -SourcePath 'C:\' -TargetDrive 'S:' -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $FilePath -eq 'bcdboot' -and
                    $ArgumentList -contains $expectedWindowsPath -and
                    $ArgumentList -contains '/s' -and
                    $ArgumentList -contains 'S:' -and
                    $ArgumentList -contains '/f' -and
                    $ArgumentList -contains 'UEFI'
                }

                $result.Success | Should -BeTrue
            }
        }
    }
}

# ============================================================================
# Find-Oscdimg
# ============================================================================

Describe 'Find-Oscdimg' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
    }

    Context 'oscdimg.exe discovery' {

        It 'Returns path when file exists at a known location' {
            InModuleScope 'Write-BootableMedia' {
                # Mock Test-Path to return true for the first candidate path
                Mock Test-Path { return $true } -ParameterFilter { $LiteralPath -like '*oscdimg.exe' }

                $result = Find-Oscdimg

                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeLike '*oscdimg.exe'
            }
        }

        It 'Returns $null when oscdimg.exe is not found anywhere' {
            InModuleScope 'Write-BootableMedia' {
                # Mock Test-Path to always return false
                Mock Test-Path { return $false } -ParameterFilter { $LiteralPath -like '*oscdimg.exe' }
                # Mock Get-ChildItem for the wildcard fallback
                Mock Get-ChildItem { return @() }

                $result = Find-Oscdimg

                $result | Should -BeNullOrEmpty
            }
        }
    }
}

# ============================================================================
# Confirm-DriveSelection
# ============================================================================

Describe 'Confirm-DriveSelection' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
    }

    Context 'ShouldProcess integration' {

        It 'Returns $false when -WhatIf is specified (ShouldProcess returns false)' {
            InModuleScope 'Write-BootableMedia' {
                $result = Confirm-DriveSelection -DiskNumber 2 -DriveLetter 'E' -WhatIf

                $result | Should -BeFalse
            }
        }

        It 'Supports the DiskNumber parameter' {
            InModuleScope 'Write-BootableMedia' {
                # With WhatIf, we can verify the function accepts the parameter without prompting
                $result = Confirm-DriveSelection -DiskNumber 5 -WhatIf

                $result | Should -BeFalse
            }
        }

        It 'Supports the optional DriveLetter parameter' {
            InModuleScope 'Write-BootableMedia' {
                $result = Confirm-DriveSelection -DiskNumber 3 -DriveLetter 'F' -WhatIf

                $result | Should -BeFalse
            }
        }
    }
}
