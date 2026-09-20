#Requires -Version 5.1

# TestHelpers.ps1 — Shared mock utilities for WinToMac Pester tests

function global:New-MockBackupJson {
    <#
    .SYNOPSIS
        Creates a valid backup JSON structure for testing Restore-OriginalSettings.

    .DESCRIPTION
        Builds an ordered hashtable matching the schema produced by
        Backup-CurrentSettings, with sample registry values covering DWord,
        String, ExpandString, Binary (base64-encoded), and null entries.

    .PARAMETER IncludeNullValues
        When set, some registry entries are stored as $null to test the
        remove-on-restore path.

    .PARAMETER AsJson
        When set, returns the JSON string instead of the hashtable.
    #>
    param(
        [switch]$IncludeNullValues,
        [switch]$AsJson
    )

    $explorerAdvanced = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $search           = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Search'
    $stuckRects       = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    $personalize      = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $accent           = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Accent'
    $startMenu        = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Start'
    $desktop          = 'HKCU:\Control Panel\Desktop'
    $cursors          = 'HKCU:\Control Panel\Cursors'

    # Build the registry snapshot with sample values
    $registry = [ordered]@{}

    # Taskbar keys
    $registry["$explorerAdvanced\TaskbarAl"]          = 0
    $registry["$explorerAdvanced\TaskbarSi"]          = 1
    $registry["$explorerAdvanced\ShowTaskViewButton"]  = 1
    $registry["$explorerAdvanced\TaskbarDa"]          = 1
    $registry["$search\SearchboxTaskbarMode"]          = 1
    $registry["$stuckRects\Settings"]                 = @{ _type = 'Binary'; Value = [Convert]::ToBase64String([byte[]](0x30, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00)) }

    # Visual style keys
    $registry["$personalize\AppsUseLightTheme"]    = 1
    $registry["$personalize\SystemUsesLightTheme"] = 1
    $registry["$personalize\EnableTransparency"]   = 1
    $registry["$personalize\ColorPrevalence"]      = 0
    $registry["$accent\AccentColorMenu"]           = 0xFFD83B01
    $registry["$accent\AccentPalette"]             = @{ _type = 'Binary'; Value = [Convert]::ToBase64String([byte[]](0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)) }

    # Start menu keys
    $registry["$explorerAdvanced\Start_Layout"]    = 0
    $registry["$startMenu\VisiblePlaces"]          = @{ _type = 'Binary'; Value = [Convert]::ToBase64String([byte[]](0x00, 0x00, 0x00, 0x00)) }

    # Wallpaper keys
    $registry["$desktop\Wallpaper"]      = 'C:\Windows\web\wallpaper\theme1.jpg'
    $registry["$desktop\WallpaperStyle"] = '10'
    $registry["$desktop\TileWallpaper"]  = '0'

    # Cursor keys
    if ($IncludeNullValues) {
        $registry["$cursors\(Default)"]   = $null
        $registry["$cursors\Arrow"]       = $null
    }
    else {
        $registry["$cursors\(Default)"]   = 'Windows Default'
        $registry["$cursors\Arrow"]       = '%SystemRoot%\cursors\aero_arrow.cur'
    }
    $registry["$cursors\Help"]         = '%SystemRoot%\cursors\aero_helpsel.cur'
    $registry["$cursors\AppStarting"]  = '%SystemRoot%\cursors\aero_working.ani'
    $registry["$cursors\Wait"]         = '%SystemRoot%\cursors\aero_busy.ani'
    $registry["$cursors\Crosshair"]    = ''
    $registry["$cursors\IBeam"]        = ''
    $registry["$cursors\NWPen"]        = '%SystemRoot%\cursors\aero_pen.cur'
    $registry["$cursors\No"]           = '%SystemRoot%\cursors\aero_unavail.cur'
    $registry["$cursors\SizeNS"]       = '%SystemRoot%\cursors\aero_ns.cur'
    $registry["$cursors\SizeWE"]       = '%SystemRoot%\cursors\aero_ew.cur'
    $registry["$cursors\SizeNWSE"]     = '%SystemRoot%\cursors\aero_nwse.cur'
    $registry["$cursors\SizeNESW"]     = '%SystemRoot%\cursors\aero_nesw.cur'
    $registry["$cursors\SizeAll"]      = '%SystemRoot%\cursors\aero_move.cur'
    $registry["$cursors\UpArrow"]      = '%SystemRoot%\cursors\aero_up.cur'
    $registry["$cursors\Hand"]         = ''

    $backup = [ordered]@{
        Version      = '1.0'
        Timestamp    = '2025-06-15T10:30:45.0000000Z'
        Registry     = $registry
        Wallpaper    = 'C:\Windows\web\wallpaper\theme1.jpg'
        CursorScheme = 'Windows Default'
    }

    if ($AsJson) {
        return ($backup | ConvertTo-Json -Depth 10)
    }

    return $backup
}

function global:New-MockFileInfo {
    <#
    .SYNOPSIS
        Creates a mock object that behaves like a FileInfo returned by
        Get-ChildItem, with the specified Name and FullName.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FullName
    )

    return [PSCustomObject]@{
        Name     = $Name
        FullName = $FullName
    }
}
