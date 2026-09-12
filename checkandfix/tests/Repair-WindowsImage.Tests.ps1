#Requires -Version 5.1

# Repair-WindowsImage.Tests.ps1 — Pester 5.x tests for Repair-WindowsImage.psm1

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Repair-WindowsImage.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    $moduleName = 'Repair-WindowsImage'
    if (Get-Module -Name $moduleName) {
        Remove-Module -Name $moduleName -Force
    }
}

# ============================================================================
# Write-StepResult
# ============================================================================

Describe 'Write-StepResult' {

    Context 'Output format' {

        It 'Outputs colored text with correct format [timestamp] [Status] Message' {
            $fixedTime = [datetime]::new(2025, 6, 15, 10, 30, 45)

            # Capture the Write-Host output via Mock
            Mock Write-Host {} -ModuleName 'Repair-WindowsImage'

            InModuleScope 'Repair-WindowsImage' -Parameters @{ fixedTime = $fixedTime } {
                param($fixedTime)
                Write-StepResult -Message 'Test message' -Status 'Pass' -Timestamp $fixedTime
            }

            Should -Invoke Write-Host -ModuleName 'Repair-WindowsImage' -Times 1 -ParameterFilter {
                $Object -eq '[2025-06-15 10:30:45] [Pass] Test message' -and
                $ForegroundColor -eq 'Green'
            }
        }
    }

    Context 'Status color mapping' {

        BeforeEach {
            Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        }

        It 'Uses Green for Pass status' {
            InModuleScope 'Repair-WindowsImage' {
                Write-StepResult -Message 'pass test' -Status 'Pass'
            }
            Should -Invoke Write-Host -ModuleName 'Repair-WindowsImage' -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'Green'
            }
        }

        It 'Uses Red for Fail status' {
            InModuleScope 'Repair-WindowsImage' {
                Write-StepResult -Message 'fail test' -Status 'Fail'
            }
            Should -Invoke Write-Host -ModuleName 'Repair-WindowsImage' -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'Red'
            }
        }

        It 'Uses Cyan for Info status' {
            InModuleScope 'Repair-WindowsImage' {
                Write-StepResult -Message 'info test' -Status 'Info'
            }
            Should -Invoke Write-Host -ModuleName 'Repair-WindowsImage' -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'Cyan'
            }
        }

        It 'Uses Yellow for Warning status' {
            InModuleScope 'Repair-WindowsImage' {
                Write-StepResult -Message 'warning test' -Status 'Warning'
            }
            Should -Invoke Write-Host -ModuleName 'Repair-WindowsImage' -Times 1 -ParameterFilter {
                $ForegroundColor -eq 'Yellow'
            }
        }
    }
}

# ============================================================================
# Invoke-ExternalCommand
# ============================================================================

Describe 'Invoke-ExternalCommand' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    Context 'Result object structure' {

        It 'Returns result object with correct properties' {
            InModuleScope 'Repair-WindowsImage' {
                # Mock a simple executable that succeeds
                Mock cmd.exe { } -ModuleName 'Repair-WindowsImage'

                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo hello') -Description 'Test command' -Confirm:$false

                $result | Should -Not -BeNullOrEmpty
                $result.PSObject.Properties.Name | Should -Contain 'ExitCode'
                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'Output'
                $result.PSObject.Properties.Name | Should -Contain 'Command'
                $result.PSObject.Properties.Name | Should -Contain 'Duration'
            }
        }
    }

    Context 'Exit code handling' {

        It 'Handles exit code 0 as success with default predicate' {
            InModuleScope 'Repair-WindowsImage' {
                # Use cmd /c exit 0 to set $LASTEXITCODE to 0
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 0') -Description 'Success command' -Confirm:$false

                $result.ExitCode | Should -Be 0
                $result.Success | Should -BeTrue
            }
        }

        It 'Handles non-zero exit code as failure' {
            InModuleScope 'Repair-WindowsImage' {
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 1') -Description 'Failure command' -Confirm:$false

                $result.ExitCode | Should -Be 1
                $result.Success | Should -BeFalse
            }
        }

        It 'Custom SuccessPredicate works for robocopy-style exit codes' {
            InModuleScope 'Repair-WindowsImage' {
                $robocopyPredicate = { param($code) $code -lt 8 }

                # Exit code 3 should be success with robocopy predicate
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 3') -Description 'Robocopy success' -SuccessPredicate $robocopyPredicate -Confirm:$false

                $result.ExitCode | Should -Be 3
                $result.Success | Should -BeTrue

                # Exit code 8 should be failure with robocopy predicate
                $result2 = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 8') -Description 'Robocopy failure' -SuccessPredicate $robocopyPredicate -Confirm:$false

                $result2.ExitCode | Should -Be 8
                $result2.Success | Should -BeFalse
            }
        }
    }

    Context 'WhatIf mode' {

        It 'Returns synthetic success without executing in WhatIf mode' {
            InModuleScope 'Repair-WindowsImage' {
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 1') -Description 'WhatIf test' -WhatIf

                $result.ExitCode | Should -Be 0
                $result.Success | Should -BeTrue
                $result.Output | Should -Be ''
                $result.Duration | Should -Be ([TimeSpan]::Zero)
            }
        }
    }

    Context 'Command property' {

        It 'Stores the full command line in the Command property' {
            InModuleScope 'Repair-WindowsImage' {
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'echo test') -Confirm:$false

                $result.Command | Should -Be 'cmd.exe /c echo test'
            }
        }
    }

    Context 'Duration measurement' {

        It 'Duration is a TimeSpan' {
            InModuleScope 'Repair-WindowsImage' {
                $result = Invoke-ExternalCommand -FilePath 'cmd.exe' -ArgumentList @('/c', 'exit 0') -Confirm:$false

                $result.Duration | Should -BeOfType [TimeSpan]
            }
        }
    }
}

# ============================================================================
# Invoke-DISMCheckHealth
# ============================================================================

Describe 'Invoke-DISMCheckHealth' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    It 'Calls Invoke-ExternalCommand with correct DISM CheckHealth arguments' {
        InModuleScope 'Repair-WindowsImage' {
            Mock Invoke-ExternalCommand {
                return [PSCustomObject]@{
                    ExitCode = 0; Success = $true; Output = 'mock output'
                    Command = 'dism.exe /Online /Cleanup-Image /CheckHealth'; Duration = [TimeSpan]::Zero
                }
            }

            $result = Invoke-DISMCheckHealth -Confirm:$false

            Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                $FilePath -eq 'dism.exe' -and
                $ArgumentList -contains '/Online' -and
                $ArgumentList -contains '/Cleanup-Image' -and
                $ArgumentList -contains '/CheckHealth' -and
                $Description -eq 'DISM CheckHealth'
            }

            $result.Success | Should -BeTrue
        }
    }
}

# ============================================================================
# Invoke-DISMScanHealth
# ============================================================================

Describe 'Invoke-DISMScanHealth' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    It 'Calls Invoke-ExternalCommand with correct DISM ScanHealth arguments' {
        InModuleScope 'Repair-WindowsImage' {
            Mock Invoke-ExternalCommand {
                return [PSCustomObject]@{
                    ExitCode = 0; Success = $true; Output = 'mock output'
                    Command = 'dism.exe /Online /Cleanup-Image /ScanHealth'; Duration = [TimeSpan]::Zero
                }
            }

            $result = Invoke-DISMScanHealth -Confirm:$false

            Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                $FilePath -eq 'dism.exe' -and
                $ArgumentList -contains '/Online' -and
                $ArgumentList -contains '/Cleanup-Image' -and
                $ArgumentList -contains '/ScanHealth' -and
                $Description -eq 'DISM ScanHealth'
            }

            $result.Success | Should -BeTrue
        }
    }
}

# ============================================================================
# Invoke-DISMRestoreHealth
# ============================================================================

Describe 'Invoke-DISMRestoreHealth' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    Context 'Default invocation (no Source, no LimitAccess)' {

        It 'Calls Invoke-ExternalCommand with base RestoreHealth arguments' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'dism.exe /Online /Cleanup-Image /RestoreHealth'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Invoke-DISMRestoreHealth -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $FilePath -eq 'dism.exe' -and
                    $ArgumentList -contains '/Online' -and
                    $ArgumentList -contains '/Cleanup-Image' -and
                    $ArgumentList -contains '/RestoreHealth' -and
                    $Description -eq 'DISM RestoreHealth'
                }

                $result.Success | Should -BeTrue
            }
        }
    }

    Context 'With -Source parameter' {

        It 'Appends /Source:<path> to the argument list' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Invoke-DISMRestoreHealth -Source 'D:\sources\install.wim' -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $ArgumentList -contains '/Source:D:\sources\install.wim'
                }
            }
        }
    }

    Context 'With -LimitAccess switch' {

        It 'Appends /LimitAccess to the argument list' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Invoke-DISMRestoreHealth -LimitAccess -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $ArgumentList -contains '/LimitAccess'
                }
            }
        }
    }

    Context 'With both -Source and -LimitAccess' {

        It 'Appends both /Source:<path> and /LimitAccess to the argument list' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Invoke-DISMRestoreHealth -Source 'C:\repair' -LimitAccess -Confirm:$false

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $ArgumentList -contains '/Source:C:\repair' -and
                    $ArgumentList -contains '/LimitAccess'
                }
            }
        }
    }
}

# ============================================================================
# Invoke-SFCScan
# ============================================================================

Describe 'Invoke-SFCScan' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    It 'Calls Invoke-ExternalCommand with sfc and /scannow' {
        InModuleScope 'Repair-WindowsImage' {
            Mock Invoke-ExternalCommand {
                return [PSCustomObject]@{
                    ExitCode = 0; Success = $true; Output = 'mock output'
                    Command = 'sfc /scannow'; Duration = [TimeSpan]::Zero
                }
            }

            $result = Invoke-SFCScan -Confirm:$false

            Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                $FilePath -eq 'sfc' -and
                $ArgumentList -contains '/scannow' -and
                $Description -eq 'SFC Scannow'
            }

            $result.Success | Should -BeTrue
        }
    }
}

# ============================================================================
# Start-RepairPipeline
# ============================================================================

Describe 'Start-RepairPipeline' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
    }

    Context 'All steps enabled (no skip switches)' {

        It 'Runs all four steps in sequence' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -Confirm:$false

                $result.Steps.Count | Should -Be 4
                $result.Steps[0].Name | Should -Be 'DISM CheckHealth'
                $result.Steps[1].Name | Should -Be 'DISM ScanHealth'
                $result.Steps[2].Name | Should -Be 'DISM RestoreHealth'
                $result.Steps[3].Name | Should -Be 'SFC Scannow'
                $result.OverallSuccess | Should -BeTrue
            }
        }
    }

    Context '-SkipDISM switch' {

        It 'Skips all three DISM steps when -SkipDISM is set' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -SkipDISM -Confirm:$false

                $result.Steps.Count | Should -Be 1
                $result.Steps[0].Name | Should -Be 'SFC Scannow'
                $result.OverallSuccess | Should -BeTrue
            }
        }
    }

    Context '-SkipSFC switch' {

        It 'Skips the SFC step when -SkipSFC is set' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'mock output'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -SkipSFC -Confirm:$false

                $result.Steps.Count | Should -Be 3
                $result.Steps[0].Name | Should -Be 'DISM CheckHealth'
                $result.Steps[1].Name | Should -Be 'DISM ScanHealth'
                $result.Steps[2].Name | Should -Be 'DISM RestoreHealth'
                $result.OverallSuccess | Should -BeTrue
            }
        }
    }

    Context '-ContinueOnError behavior' {

        It 'Continues past failures when -ContinueOnError is set' {
            InModuleScope 'Repair-WindowsImage' {
                $callCount = 0
                Mock Invoke-ExternalCommand {
                    $script:callCount++
                    if ($script:callCount -eq 1) {
                        return [PSCustomObject]@{
                            ExitCode = 1; Success = $false; Output = 'failed'
                            Command = 'mock'; Duration = [TimeSpan]::Zero
                        }
                    }
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'ok'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -ContinueOnError -Confirm:$false

                # All 4 steps should have run despite first step failing
                $result.Steps.Count | Should -Be 4
                $result.OverallSuccess | Should -BeFalse
            }
        }

        It 'Stops at first failure without -ContinueOnError' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 1; Success = $false; Output = 'failed'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -Confirm:$false

                # Should stop after first failure (only 1 step recorded)
                $result.Steps.Count | Should -Be 1
                $result.OverallSuccess | Should -BeFalse
            }
        }
    }

    Context 'Structured result' {

        It 'Returns structured result with Steps array and OverallSuccess' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'ok'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                $result = Start-RepairPipeline -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Steps'
                $result.PSObject.Properties.Name | Should -Contain 'OverallSuccess'
                $result.PSObject.Properties.Name | Should -Contain 'StartTime'
                $result.PSObject.Properties.Name | Should -Contain 'EndTime'
                $result.PSObject.Properties.Name | Should -Contain 'Duration'
                $result.Steps | Should -BeOfType [System.Object]
                $result.Duration | Should -BeOfType [TimeSpan]
            }
        }
    }

    Context 'Parameter pass-through to RestoreHealth' {

        It 'Passes -Source and -LimitAccess through to Invoke-DISMRestoreHealth' {
            InModuleScope 'Repair-WindowsImage' {
                Mock Invoke-ExternalCommand {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'ok'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                # We need to verify the RestoreHealth call gets Source and LimitAccess.
                # Mock Invoke-DISMRestoreHealth to capture its parameters.
                Mock Invoke-DISMRestoreHealth {
                    return [PSCustomObject]@{
                        ExitCode = 0; Success = $true; Output = 'ok'
                        Command = 'mock'; Duration = [TimeSpan]::Zero
                    }
                }

                Start-RepairPipeline -Source 'D:\repair' -LimitAccess -Confirm:$false

                Should -Invoke Invoke-DISMRestoreHealth -Times 1 -ParameterFilter {
                    $Source -eq 'D:\repair' -and
                    $LimitAccess -eq $true
                }
            }
        }
    }
}
