@{
    RootModule        = ''
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Tomas Lonnqvist'
    CompanyName       = ''
    Copyright         = '(c) 2026 Tomas Lonnqvist. All rights reserved.'
    Description       = 'Windows system repair and installation export utility using DISM, SFC, and native Windows tools.'
    PowerShellVersion = '5.1'

    NestedModules     = @(
        'src\Repair-WindowsImage.psm1',
        'src\Export-Installation.psm1',
        'src\Write-BootableMedia.psm1'
    )

    FunctionsToExport = @(
        'Invoke-ExternalCommand',
        'Write-StepResult',
        'Invoke-DISMCheckHealth',
        'Invoke-DISMScanHealth',
        'Invoke-DISMRestoreHealth',
        'Invoke-SFCScan',
        'Start-RepairPipeline',
        'Export-ToUSB',
        'Export-ToISO',
        'Start-ExportPipeline',
        'New-DiskpartScript',
        'Invoke-Diskpart',
        'Copy-InstallationFiles',
        'Set-BootConfiguration',
        'Find-Oscdimg',
        'Confirm-DriveSelection'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Windows', 'DISM', 'SFC', 'Repair', 'SystemMaintenance')
            ProjectUri = 'https://github.com/lonnqvisttomas/lonnqvisttomas.github.io'
        }
    }
}
