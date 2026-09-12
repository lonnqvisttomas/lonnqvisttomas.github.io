# CheckAndFix — Windows System Repair & Export Utility

A PowerShell 5.1 utility that automates the standard Windows repair workflow (DISM + SFC) and optionally exports the repaired installation to a bootable USB drive or ISO image.

## Prerequisites

- **Windows 10/11** or **Windows Server 2016+**
- **Windows PowerShell 5.1** (pre-installed on all supported Windows editions)
- **Administrator privileges** (required for DISM, SFC, diskpart, and export operations)
- **Windows ADK** — Deployment Tools feature (required only for ISO export; the script provides installation guidance if missing)
- **Pester 5.x** — required only for running the test suite

## Installation

No installation is required. Clone or download this repository and run the entry-point script directly:

```powershell
git clone https://github.com/lonnqvisttomas/lonnqvisttomas.github.io.git
cd lonnqvisttomas.github.io\checkandfix
```

## Usage

All commands must be run from an **elevated PowerShell prompt** (Run as Administrator).

### Repair Only (Default)

Run the full DISM + SFC repair pipeline:

```powershell
.\CheckAndFix.ps1
```

### Skip DISM or SFC

Skip DISM health checks (run SFC only):

```powershell
.\CheckAndFix.ps1 -SkipDISM
```

Skip SFC scan (run DISM only):

```powershell
.\CheckAndFix.ps1 -SkipSFC
```

### Continue on Error

By default, the pipeline stops at the first failure. To continue through all steps:

```powershell
.\CheckAndFix.ps1 -ContinueOnError
```

### Specify an Offline Repair Source

Use a local WIM/ESD file instead of Windows Update for DISM RestoreHealth:

```powershell
.\CheckAndFix.ps1 -Source "D:\sources\install.wim" -LimitAccess
```

### Repair and Export to USB

Repair the system, then create a bootable USB drive:

```powershell
.\CheckAndFix.ps1 -ExportTarget USB -DiskNumber 2 -DriveLetter "E:"
```

You will be prompted to confirm the target drive before any data is erased.

### Repair and Export to ISO

Repair the system, then create a bootable ISO image:

```powershell
.\CheckAndFix.ps1 -ExportTarget ISO
```

The ISO is saved to `%USERPROFILE%\Desktop\WindowsBackup.iso` by default. Specify a custom path:

```powershell
.\CheckAndFix.ps1 -ExportTarget ISO -OutputPath "D:\Backups\Windows.iso"
```

### Dry Run (WhatIf)

Preview all operations without making changes:

```powershell
.\CheckAndFix.ps1 -WhatIf
.\CheckAndFix.ps1 -ExportTarget USB -DiskNumber 2 -DriveLetter "E:" -WhatIf
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-SkipDISM` | Switch | Skip all DISM health checks (CheckHealth, ScanHealth, RestoreHealth) |
| `-SkipSFC` | Switch | Skip the SFC /scannow step |
| `-ExportTarget` | String | Export target: `USB` or `ISO`. Triggers the RepairAndExport parameter set |
| `-DiskNumber` | Int | USB disk number for USB export (use `Get-Disk` to identify) |
| `-DriveLetter` | String | Target drive letter for USB export (e.g., `"E:"`) |
| `-OutputPath` | String | Output file path for ISO export. Default: `$env:USERPROFILE\Desktop\WindowsBackup.iso` |
| `-Source` | String | Offline WIM/ESD source path for DISM RestoreHealth |
| `-LimitAccess` | Switch | Prevent DISM from using Windows Update as a repair source |
| `-LogDirectory` | String | Transcript log directory. Default: `$env:TEMP\CheckAndFix` |
| `-ContinueOnError` | Switch | Continue the repair pipeline even if a step fails |
| `-WhatIf` | Switch | Preview all operations without executing them |
| `-Verbose` | Switch | Show detailed diagnostic output |

## Export Targets

### USB

Creates a bootable UEFI USB drive using native Windows tools:

1. **diskpart** — cleans, partitions (GPT), and formats the target drive
2. **robocopy** — copies Windows installation files
3. **bcdboot** — configures UEFI boot

**Warning:** This operation erases all data on the target drive. A confirmation prompt is displayed before proceeding.

### ISO

Creates a bootable ISO image with dual-boot support (BIOS + UEFI) using `oscdimg.exe` from the Windows ADK.

If `oscdimg.exe` is not found, the script displays installation guidance:

1. Download the Windows ADK from [Microsoft](https://go.microsoft.com/fwlink/?linkid=2243390)
2. During installation, select the **Deployment Tools** feature
3. Re-run the export command

## Running Tests

Install Pester and run the test suite:

```powershell
Install-Module Pester -Force -Scope CurrentUser
.\Run-Tests.ps1
```

Test results are written to `test-results.xml` (NUnit XML format). Code coverage is reported against the `src/` directory.

Tests mock all external system commands and run without administrator privileges.

## Project Structure

```
checkandfix/
├── CheckAndFix.ps1          # Entry-point script
├── CheckAndFix.psd1         # Module manifest
├── src/
│   ├── Repair-WindowsImage.psm1   # DISM/SFC repair pipeline
│   ├── Export-Installation.psm1   # USB and ISO export orchestration
│   └── Write-BootableMedia.psm1   # Bootable media creation helpers
├── tests/
│   ├── Repair-WindowsImage.Tests.ps1
│   ├── Export-Installation.Tests.ps1
│   └── Write-BootableMedia.Tests.ps1
├── Run-Tests.ps1            # Test runner with coverage config
└── README.md                # This file
```

## Troubleshooting

- **"Access denied" errors** — Run PowerShell as Administrator. DISM, SFC, and diskpart require elevated privileges.
- **DISM RestoreHealth fails** — Windows Update may be unreachable. Use `-Source` with a local WIM/ESD file and `-LimitAccess`.
- **oscdimg.exe not found** — Install the Windows ADK Deployment Tools feature.
- **Robocopy reports "extra files"** — Exit codes 1–7 from robocopy indicate copied/skipped/extra files and are treated as success. Only exit codes 8+ indicate errors.
- **USB drive not recognized after export** — Ensure the drive is large enough and retry. Check that the BIOS/UEFI is set to boot from USB.
