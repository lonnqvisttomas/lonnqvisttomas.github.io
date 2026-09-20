@{
    RootModule        = ''
    ModuleVersion     = '1.0.0'
    GUID              = 'b2c3d4e5-f6a7-8901-bcde-f12345678901'
    Author            = 'Tomas Lonnqvist'
    CompanyName       = ''
    Copyright         = '(c) 2026 Tomas Lonnqvist. All rights reserved.'
    Description       = 'Windows 11 to macOS theme conversion module with backup/restore support.'
    PowerShellVersion = '5.1'

    NestedModules     = @(
        'src\Backup-CurrentSettings.psm1',
        'src\Restore-OriginalSettings.psm1',
        'src\Set-TaskbarConfig.psm1',
        'src\Set-VisualStyle.psm1',
        'src\Set-Wallpaper.psm1',
        'src\Set-CursorScheme.psm1',
        'src\Set-StartMenuConfig.psm1',
        'src\Invoke-ExplorerRestart.psm1'
    )

    FunctionsToExport = @(
        'Backup-CurrentSettings',
        'Restore-OriginalSettings',
        'Set-TaskbarConfig',
        'Set-VisualStyle',
        'Set-Wallpaper',
        'Set-CursorScheme',
        'Set-StartMenuConfig',
        'Invoke-ExplorerRestart'
    )

    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport    = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Windows', 'macOS', 'Theme', 'Customization', 'Registry')
            ProjectUri = 'https://github.com/lonnqvisttomas/lonnqvisttomas.github.io'
        }
    }
}
