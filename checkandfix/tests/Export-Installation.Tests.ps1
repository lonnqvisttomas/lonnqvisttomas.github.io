#Requires -Version 5.1

# Export-Installation.Tests.ps1 — Pester 5.x tests for Export-Installation.psm1

BeforeAll {
    . (Join-Path -Path $PSScriptRoot -ChildPath 'TestHelpers.ps1')
    # Import all dependent modules in the correct order
    $repairModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Repair-WindowsImage.psm1'
    Import-Module -Name $repairModulePath -Force

    $bootMediaModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Write-BootableMedia.psm1'
    Import-Module -Name $bootMediaModulePath -Force

    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\src\Export-Installation.psm1'
    Import-Module -Name $modulePath -Force
}

AfterAll {
    if (Get-Module -Name 'Export-Installation') {
        Remove-Module -Name 'Export-Installation' -Force
    }
    if (Get-Module -Name 'Write-BootableMedia') {
        Remove-Module -Name 'Write-BootableMedia' -Force
    }
    if (Get-Module -Name 'Repair-WindowsImage') {
        Remove-Module -Name 'Repair-WindowsImage' -Force
    }
}

# ============================================================================
# Export-ToUSB
# ============================================================================

Describe 'Export-ToUSB' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
        Mock Write-Host {} -ModuleName 'Export-Installation'
    }

    Context 'Full success path — all steps succeed' {

        It 'Returns Success=$true when all steps complete successfully' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $true }

                # Return a real temp file so Invoke-Diskpart ValidateScript passes
                $tempFile = [System.IO.Path]::GetTempFileName()
                Mock New-DiskpartScript { return $tempFile }

                Mock Invoke-Diskpart {
                    return (New-MockCommandResult -Output 'mock')
                }

                Mock Copy-InstallationFiles {
                    return (New-MockCommandResult -Output 'mock')
                }

                Mock Set-BootConfiguration {
                    return (New-MockCommandResult -Output 'mock')
                }

                try {
                    $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -SourcePath 'C:\' -Confirm:$false

                    $result.Success | Should -BeTrue
                    $result.ExportTarget | Should -Be 'USB'
                    $result.Steps.Count | Should -Be 4

                    Should -Invoke Confirm-DriveSelection -Times 1
                    Should -Invoke New-DiskpartScript -Times 1
                    Should -Invoke Invoke-Diskpart -Times 1
                    Should -Invoke Copy-InstallationFiles -Times 1
                    Should -Invoke Set-BootConfiguration -Times 1
                } finally {
                    if (Test-Path -LiteralPath $tempFile) {
                        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Context 'Abort when drive confirmation fails' {

        It 'Returns Success=$false and stops when Confirm-DriveSelection returns $false' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $false }

                Mock New-DiskpartScript {}
                Mock Invoke-Diskpart {}
                Mock Copy-InstallationFiles {}
                Mock Set-BootConfiguration {}

                $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -Confirm:$false

                $result.Success | Should -BeFalse
                $result.ExportTarget | Should -Be 'USB'
                $result.Steps.Count | Should -Be 1

                Should -Invoke Confirm-DriveSelection -Times 1
                Should -Invoke New-DiskpartScript -Times 0
                Should -Invoke Invoke-Diskpart -Times 0
                Should -Invoke Copy-InstallationFiles -Times 0
                Should -Invoke Set-BootConfiguration -Times 0
            }
        }
    }

    Context 'Abort when diskpart fails' {

        It 'Returns Success=$false and stops when Invoke-Diskpart fails' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $true }

                $tempFile = [System.IO.Path]::GetTempFileName()
                Mock New-DiskpartScript { return $tempFile }

                Mock Invoke-Diskpart {
                    return (New-MockCommandResult -ExitCode 1 -Success $false -Output 'diskpart failed')
                }

                Mock Copy-InstallationFiles {}
                Mock Set-BootConfiguration {}

                try {
                    $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -SourcePath 'C:\' -Confirm:$false

                    $result.Success | Should -BeFalse
                    $result.Steps.Count | Should -Be 2

                    Should -Invoke Copy-InstallationFiles -Times 0
                    Should -Invoke Set-BootConfiguration -Times 0
                } finally {
                    if (Test-Path -LiteralPath $tempFile) {
                        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Context 'Abort when robocopy (Copy-InstallationFiles) fails' {

        It 'Returns Success=$false and stops when file copy fails' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $true }

                $tempFile = [System.IO.Path]::GetTempFileName()
                Mock New-DiskpartScript { return $tempFile }

                Mock Invoke-Diskpart {
                    return (New-MockCommandResult -Output 'ok')
                }

                Mock Copy-InstallationFiles {
                    return (New-MockCommandResult -ExitCode 8 -Success $false -Output 'copy failed')
                }

                Mock Set-BootConfiguration {}

                try {
                    $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -SourcePath 'C:\' -Confirm:$false

                    $result.Success | Should -BeFalse
                    $result.Steps.Count | Should -Be 3

                    Should -Invoke Set-BootConfiguration -Times 0
                } finally {
                    if (Test-Path -LiteralPath $tempFile) {
                        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Context 'Abort when Set-BootConfiguration (bcdboot) fails' {

        It 'Returns failure with 4 steps when boot configuration fails' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $true }

                $tempFile = [System.IO.Path]::GetTempFileName()
                Mock New-DiskpartScript { return $tempFile }

                Mock Invoke-Diskpart {
                    return (New-MockCommandResult -Output 'ok')
                }
                Mock Copy-InstallationFiles {
                    return (New-MockCommandResult -Output 'ok')
                }
                Mock Set-BootConfiguration {
                    return (New-MockCommandResult -ExitCode 1 -Success $false -Output 'bcdboot failed')
                }

                try {
                    $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -SourcePath 'C:\' -Confirm:$false

                    $result.Success | Should -BeFalse
                    $result.Steps.Count | Should -Be 4

                    Should -Invoke Set-BootConfiguration -Times 1
                } finally {
                    if (Test-Path -LiteralPath $tempFile) {
                        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }

    Context 'Result structure' {

        It 'Returns result with expected properties' {
            InModuleScope 'Export-Installation' {
                Mock Confirm-DriveSelection { return $true }

                $tempFile = [System.IO.Path]::GetTempFileName()
                Mock New-DiskpartScript { return $tempFile }

                Mock Invoke-Diskpart {
                    return (New-MockCommandResult -Output 'ok')
                }
                Mock Copy-InstallationFiles {
                    return (New-MockCommandResult -Output 'ok')
                }
                Mock Set-BootConfiguration {
                    return (New-MockCommandResult -Output 'ok')
                }

                try {
                    $result = Export-ToUSB -DiskNumber 2 -DriveLetter 'E:' -Confirm:$false

                    $result.PSObject.Properties.Name | Should -Contain 'Success'
                    $result.PSObject.Properties.Name | Should -Contain 'Steps'
                    $result.PSObject.Properties.Name | Should -Contain 'ExportTarget'
                    $result.PSObject.Properties.Name | Should -Contain 'StartTime'
                    $result.PSObject.Properties.Name | Should -Contain 'EndTime'
                    $result.PSObject.Properties.Name | Should -Contain 'Duration'
                } finally {
                    if (Test-Path -LiteralPath $tempFile) {
                        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}

# ============================================================================
# Export-ToISO
# ============================================================================

Describe 'Export-ToISO' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
        Mock Write-Host {} -ModuleName 'Export-Installation'
    }

    Context 'oscdimg found — successful ISO creation' {

        It 'Calls Invoke-ExternalCommand with oscdimg arguments when Find-Oscdimg returns a path' {
            InModuleScope 'Export-Installation' {
                Mock Find-Oscdimg { return 'C:\ADK\oscdimg.exe' }

                Mock Test-Path { return $true } -ParameterFilter { $PathType -eq 'Container' }

                Mock Invoke-ExternalCommand {
                    return (New-MockCommandResult -Output 'iso created')
                }

                # Use C:\ paths that exist as drives to avoid DriveNotFoundException from Split-Path
                $outputPath = Join-Path -Path $env:TEMP -ChildPath 'test-backup.iso'
                $result = Export-ToISO -SourcePath 'C:\WinInstall' -OutputPath $outputPath -Confirm:$false

                $result.Success | Should -BeTrue
                $result.ExportTarget | Should -Be 'ISO'
                $result.OscdimgPath | Should -Be 'C:\ADK\oscdimg.exe'

                Should -Invoke Invoke-ExternalCommand -Times 1 -ParameterFilter {
                    $FilePath -eq 'C:\ADK\oscdimg.exe'
                }
            }
        }
    }

    Context 'oscdimg not found' {

        It 'Returns Success=$false and a guidance message when Find-Oscdimg returns $null' {
            InModuleScope 'Export-Installation' {
                Mock Find-Oscdimg { return $null }

                $result = Export-ToISO -Confirm:$false

                $result.Success | Should -BeFalse
                $result.ExportTarget | Should -Be 'ISO'
                $result.OscdimgPath | Should -BeNullOrEmpty
                $result.GuidanceMessage | Should -Not -BeNullOrEmpty
                $result.GuidanceMessage | Should -Match 'oscdimg.exe was not found'
                $result.GuidanceMessage | Should -Match 'Windows Assessment and Deployment Kit'
            }
        }
    }

    Context 'oscdimg found — execution failure' {

        It 'Returns Success=$false when oscdimg invocation fails with non-zero exit code' {
            InModuleScope 'Export-Installation' {
                Mock Find-Oscdimg { return 'C:\ADK\oscdimg.exe' }
                Mock Test-Path { return $true } -ParameterFilter { $PathType -eq 'Container' }

                Mock Invoke-ExternalCommand {
                    return (New-MockCommandResult -ExitCode 1 -Success $false -Output 'oscdimg failed')
                }

                $outputPath = Join-Path -Path $env:TEMP -ChildPath 'test-fail.iso'
                $result = Export-ToISO -SourcePath 'C:\WinInstall' -OutputPath $outputPath -Confirm:$false

                $result.Success | Should -BeFalse
                $result.ExitCode | Should -Be 1
            }
        }
    }

    Context 'Default OutputPath' {

        It 'Uses Desktop\WindowsBackup.iso as the default output path' {
            InModuleScope 'Export-Installation' {
                Mock Find-Oscdimg { return $null }

                $expectedDefault = "$env:USERPROFILE\Desktop\WindowsBackup.iso"
                $result = Export-ToISO -Confirm:$false

                $result.OutputPath | Should -Be $expectedDefault
            }
        }
    }

    Context 'Result structure' {

        It 'Returns result with expected properties on success' {
            InModuleScope 'Export-Installation' {
                Mock Find-Oscdimg { return 'C:\ADK\oscdimg.exe' }
                Mock Test-Path { return $true } -ParameterFilter { $PathType -eq 'Container' }
                Mock Invoke-ExternalCommand {
                    return (New-MockCommandResult -Output 'ok')
                }

                $isoOutputPath = Join-Path -Path $env:TEMP -ChildPath 'test.iso'
                $result = Export-ToISO -SourcePath 'C:\' -OutputPath $isoOutputPath -Confirm:$false

                $result.PSObject.Properties.Name | Should -Contain 'Success'
                $result.PSObject.Properties.Name | Should -Contain 'OutputPath'
                $result.PSObject.Properties.Name | Should -Contain 'ExportTarget'
                $result.PSObject.Properties.Name | Should -Contain 'OscdimgPath'
                $result.PSObject.Properties.Name | Should -Contain 'StartTime'
                $result.PSObject.Properties.Name | Should -Contain 'EndTime'
                $result.PSObject.Properties.Name | Should -Contain 'Duration'
            }
        }
    }
}

# ============================================================================
# Start-ExportPipeline
# ============================================================================

Describe 'Start-ExportPipeline' {

    BeforeEach {
        Mock Write-Host {} -ModuleName 'Repair-WindowsImage'
        Mock Write-Host {} -ModuleName 'Write-BootableMedia'
        Mock Write-Host {} -ModuleName 'Export-Installation'
    }

    Context 'USB routing' {

        It 'Routes to Export-ToUSB when ExportTarget is USB' {
            InModuleScope 'Export-Installation' {
                Mock Export-ToUSB {
                    return [PSCustomObject]@{
                        Success      = $true
                        Steps        = @()
                        ExportTarget = 'USB'
                        StartTime    = Get-Date
                        EndTime      = Get-Date
                        Duration     = [TimeSpan]::Zero
                    }
                }

                Mock Export-ToISO {}

                $result = Start-ExportPipeline -ExportTarget 'USB' -DiskNumber 2 -DriveLetter 'E:' -Confirm:$false

                $result.Success | Should -BeTrue
                $result.ExportTarget | Should -Be 'USB'

                Should -Invoke Export-ToUSB -Times 1
                Should -Invoke Export-ToISO -Times 0
            }
        }
    }

    Context 'ISO routing' {

        It 'Routes to Export-ToISO when ExportTarget is ISO' {
            InModuleScope 'Export-Installation' {
                Mock Export-ToUSB {}

                Mock Export-ToISO {
                    return [PSCustomObject]@{
                        Success      = $true
                        OutputPath   = 'D:\test.iso'
                        ExportTarget = 'ISO'
                        OscdimgPath  = 'C:\ADK\oscdimg.exe'
                        StartTime    = Get-Date
                        EndTime      = Get-Date
                        Duration     = [TimeSpan]::Zero
                    }
                }

                $result = Start-ExportPipeline -ExportTarget 'ISO' -Confirm:$false

                $result.Success | Should -BeTrue
                $result.ExportTarget | Should -Be 'ISO'

                Should -Invoke Export-ToISO -Times 1
                Should -Invoke Export-ToUSB -Times 0
            }
        }
    }

    Context 'USB parameter validation' {

        It 'Throws when DiskNumber is not provided for USB export' {
            InModuleScope 'Export-Installation' {
                {
                    Start-ExportPipeline -ExportTarget 'USB' -DriveLetter 'E:' -Confirm:$false
                } | Should -Throw '*DiskNumber*'
            }
        }

        It 'Throws when DriveLetter is not provided for USB export' {
            InModuleScope 'Export-Installation' {
                {
                    Start-ExportPipeline -ExportTarget 'USB' -DiskNumber 2 -Confirm:$false
                } | Should -Throw '*DriveLetter*'
            }
        }

        It 'Throws when an invalid ExportTarget value is provided' {
            InModuleScope 'Export-Installation' {
                {
                    Start-ExportPipeline -ExportTarget 'DVD' -Confirm:$false
                } | Should -Throw
            }
        }
    }

    Context 'SourcePath pass-through' {

        It 'Passes SourcePath to Export-ToUSB for USB exports' {
            InModuleScope 'Export-Installation' {
                Mock Export-ToUSB {
                    return [PSCustomObject]@{
                        Success      = $true
                        Steps        = @()
                        ExportTarget = 'USB'
                        StartTime    = Get-Date
                        EndTime      = Get-Date
                        Duration     = [TimeSpan]::Zero
                    }
                }

                Start-ExportPipeline -ExportTarget 'USB' -DiskNumber 2 -DriveLetter 'E:' -SourcePath 'D:\WinSource' -Confirm:$false

                Should -Invoke Export-ToUSB -Times 1 -ParameterFilter {
                    $SourcePath -eq 'D:\WinSource'
                }
            }
        }

        It 'Passes SourcePath to Export-ToISO for ISO exports' {
            InModuleScope 'Export-Installation' {
                Mock Export-ToISO {
                    return [PSCustomObject]@{
                        Success      = $true
                        OutputPath   = 'D:\test.iso'
                        ExportTarget = 'ISO'
                        OscdimgPath  = $null
                        StartTime    = Get-Date
                        EndTime      = Get-Date
                        Duration     = [TimeSpan]::Zero
                    }
                }

                Start-ExportPipeline -ExportTarget 'ISO' -SourcePath 'D:\WinSource' -Confirm:$false

                Should -Invoke Export-ToISO -Times 1 -ParameterFilter {
                    $SourcePath -eq 'D:\WinSource'
                }
            }
        }
    }

    Context 'OutputPath pass-through for ISO' {

        It 'Passes OutputPath to Export-ToISO when provided' {
            InModuleScope 'Export-Installation' {
                Mock Export-ToISO {
                    return [PSCustomObject]@{
                        Success      = $true
                        OutputPath   = 'E:\custom.iso'
                        ExportTarget = 'ISO'
                        OscdimgPath  = $null
                        StartTime    = Get-Date
                        EndTime      = Get-Date
                        Duration     = [TimeSpan]::Zero
                    }
                }

                Start-ExportPipeline -ExportTarget 'ISO' -OutputPath 'E:\custom.iso' -Confirm:$false

                Should -Invoke Export-ToISO -Times 1 -ParameterFilter {
                    $OutputPath -eq 'E:\custom.iso'
                }
            }
        }
    }
}
