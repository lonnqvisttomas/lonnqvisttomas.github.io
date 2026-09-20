# WinToMac — Windows 11 to macOS Theme Conversion

A PowerShell 5.1 module that transforms a Windows 11 desktop to resemble macOS and cleanly reverts the changes.

## Features

- **Taskbar/Dock** — Auto-hide, center icons, small size, remove search box/task view/widgets
- **Visual Style** — Dark/light mode, macOS-inspired blue accent, transparency, title-bar color
- **Wallpaper** — Deploy and apply macOS-style wallpaper
- **Cursor Scheme** — Install and activate macOS-style cursors
- **Start Menu** — Adjust positioning and behavior for macOS-like experience
- **Full Backup/Restore** — Every change is captured before modification and can be reverted

## Requirements

- Windows 10 version 1903+ or Windows 11
- Windows PowerShell 5.1 (pre-installed)
- Pester 5.x for running tests: `Install-Module Pester -Force -Scope CurrentUser`

## Usage

```powershell
# Apply the full macOS theme
.\wintomac\Install-MacTheme.ps1

# Preview changes without applying
.\wintomac\Install-MacTheme.ps1 -WhatIf

# Skip specific features
.\wintomac\Install-MacTheme.ps1 -SkipDock -SkipCursors

# Use a JSON config file for customization
.\wintomac\Install-MacTheme.ps1 -ConfigPath .\my-config.json

# Revert to original Windows settings
.\wintomac\Uninstall-MacTheme.ps1

# Run the Pester test suite
.\wintomac\Run-Tests.ps1
```

## Parameters

### Install-MacTheme.ps1

| Parameter | Description |
|-----------|-------------|
| `-SkipDock` | Skip taskbar/dock customization |
| `-SkipCursors` | Skip cursor scheme installation |
| `-SkipWallpaper` | Skip wallpaper deployment |
| `-SkipStartMenu` | Skip Start menu configuration |
| `-SkipVisualStyle` | Skip visual style changes |
| `-ConfigPath` | Path to a JSON config file for advanced customization |
| `-NoRestart` | Suppress the Explorer restart prompt |
| `-WhatIf` | Preview all operations without executing |

### Uninstall-MacTheme.ps1

| Parameter | Description |
|-----------|-------------|
| `-NoRestart` | Suppress the Explorer restart prompt |
| `-WhatIf` | Preview all operations without executing |

## Cursor and Wallpaper Assets

The `assets/cursors/` and `assets/wallpapers/` directories contain placeholder files. Users should supply their own macOS-style cursor pack (`.cur`/`.ani` files) and wallpaper images. The module gracefully skips cursor and wallpaper installation if asset files are missing.

## Project Structure

```
wintomac/
├── Install-MacTheme.ps1         # Entry point: apply macOS theme
├── Uninstall-MacTheme.ps1       # Entry point: revert to Windows defaults
├── WinToMac.psd1                # Module manifest
├── Run-Tests.ps1                # Pester test runner
├── .gitignore
├── README.md
├── src/
│   ├── Backup-CurrentSettings.psm1
│   ├── Restore-OriginalSettings.psm1
│   ├── Set-TaskbarConfig.psm1
│   ├── Set-VisualStyle.psm1
│   ├── Set-Wallpaper.psm1
│   ├── Set-CursorScheme.psm1
│   └── Set-StartMenuConfig.psm1
├── assets/
│   ├── wallpapers/
│   └── cursors/
└── tests/
    ├── TestHelpers.ps1
    ├── Backup-CurrentSettings.Tests.ps1
    ├── Restore-OriginalSettings.Tests.ps1
    ├── Set-TaskbarConfig.Tests.ps1
    ├── Set-VisualStyle.Tests.ps1
    ├── Set-Wallpaper.Tests.ps1
    ├── Set-CursorScheme.Tests.ps1
    └── Set-StartMenuConfig.Tests.ps1
```

## Admin Privileges

Most theming changes target `HKCU` (current-user) keys and do not require elevation. System-wide cursor scheme registration under `HKLM` may require administrator privileges. The module falls back to per-user `HKCU` cursor registration if `HKLM` access is denied.

## Backup Location

Settings are backed up to `$env:APPDATA\WinToMac\backup.json`. This file is required for uninstallation. Do not delete it manually if you intend to revert changes.
