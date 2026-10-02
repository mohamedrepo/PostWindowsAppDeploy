# Freebuff Auto-Download Deployment

A PowerShell-based deployment tool that **automatically downloads updated install
packages from official sources** — Visual C++ redistributables, OneDrive, App
Installer, Intel/NVIDIA drivers, and the Freebuff/Autoclaw toolchains — then deploys
them with the original `installV2.ps1` engine (skip-already-installed menu, exit
codes `0` / `3010` / `1641`, CSV report).

## Features

- **Official-source downloads** — every package is fetched from its official
  vendor page or GitHub release (no third-party mirrors).
- **SHA-256 checksum verification** — each downloaded file is verified against a
  manifest (`checksums.sha256`).
- **Driver refresh** — `install-drivers.ps1` probes the official Intel, NVIDIA, and
  Broadcom (SEP) portals, downloads the drivers into `C:\Applications\Drivers`,
  and records SHA-256 hashes in `driver-manifest.txt`. Requires confirmation
  before continuing.
- **Interactive deployment menu** — select A (all) or a comma-separated list of
  IDs; each installer runs with the original silent arguments.
- **Standard exit codes** — `0` (success), `3010` (reboot required), `1641` (reboot
  initiated).
- **CSV report** — writes `Deployment_YYYY-MM-DD_HHMMSS.csv` to
  `C:\Applications\Reports`.

## Repository contents

| File | Purpose |
|------|---------|
| `installV2.ps1` | The deployment engine. Download phase → checksum verification → app definitions → interactive menu → deployment → report. |
| `install-drivers.ps1` | Helper script to refresh Intel/NVIDIA drivers and Symantec Endpoint Protection (SEP) from official sources. |
| `install.ps1` | Original interactive installer (kept for reference). |
| `Freebuff_auto_download_README.md` | Original project documentation. |
| `SEPx64\` | Symantec Endpoint Protection bundle (SmcInst.exe, definition ZIPs, configuration). |
| `Office2024X64EnAr\` | Office deployment config + ODT.exe. |

## Included applications & official sources

| App | Official source |
|-----|-----------------|
| Internet Download Manager | https://www.internetdownloadmanager.com/download.html |
| VMware Workstation Pro | https://www.vmware.com/go/getwebclient |
| Notepad++ | https://notepad-plus-plus.org/downloads/ |
| K-Lite Codec Mega | https://www.codecguide.com/download_k-lite_codec_pack_mega.htm |
| Adobe Acrobat Reader | https://get.adobe.com/reader/ |
| Google Chrome | https://www.google.com/chrome/ |
| Power BI Desktop | https://aka.ms/PBIDesktop |
| Microsoft Office 2024 | https://www.microsoft.com/en-us/microsoft-365/product-office |
| Freebuff | https://github.com/freebuff/freebuff/releases/latest |
| Autoclaw | https://github.com/freebuff/autoclaw/releases/latest |
| Git | https://github.com/git-for-windows/git/releases/latest |
| Visual Studio Code | https://code.visualstudio.com/Updates |
| Security Health Setup | https://www.microsoft.com/.../securityhealthsetup |
| Intel Graphics Driver | https://downloadcenter.intel.com/product/139236/Intel-Graphics-Drivers |
| NVIDIA Graphics Driver | https://www.nvidia.com/Download/DriverProfile.aspx |
| Visual C++ 2015-2022 Redistributable x64 | https://aka.ms/vs/17/release/vc_redist.x64.exe |
| Visual C++ 2015-2022 Redistributable x86 | https://aka.ms/vs/17/release/vc_redist.x86.exe |
| Microsoft OneDrive | https://www.microsoft.com/en-us/microsoft-365/onedrive/download |
| Microsoft App Installer | https://apps.microsoft.com/store/search?hl=en-us&gl=us |
| Symantec Endpoint Protection | https://broadcom.com/go/endpoint-protection |

> **Note:** Driver and SEP URLs point at the official *download portals*, which
> redirect to the latest matching driver/SEP version. The actual file checksums are
> not known ahead of time, so the script downloads the portal page or the
> versioned installer rather than pinning a single hardcoded checksum.

## How it works

1. **Download phase** — `installV2.ps1` downloads each item from its official
   source into `C:\Applications\Downloads`.
2. **Checksum verification** — each downloaded file is verified against a SHA-256
   manifest (`checksums.sha256`).
3. **Driver & SEP handling** — `install-drivers.ps1` refreshes the Intel/NVIDIA
   drivers and Symantec Endpoint Protection from official sources, and records the
   current version.
4. **Deployment phase** — the interactive menu runs each package with the
   appropriate silent arguments.

## Usage

Open PowerShell **as Administrator** and run:

```powershell
# Preview the download list and targets (no downloads)
.\installV2.ps1 -WhatIf

# Download everything and deploy (interactive selection)
.\installV2.ps1

# Re-download only (ignore cached files)
.\installV2.ps1 -Force
```

## Updating a package

To update a specific package, change its `Source` URL in the `$DownloadEntries`
array inside `installV2.ps1` (see the `# DOWNLOAD PHASE` section), then re-run the
script. Files that already exist and pass checksum verification will be reused.

## Security note

- All download URLs point at **official vendor sites** or official GitHub
  repositories.
- Driver packages are large; always review the SHA-256/MD5 hash shown on the
  vendor's page before installing.
- SEP / endpoint protection must never be disabled during remote work or
  outbound transfer. The bundled `SEPx64` folder contains the Symantec
  endpoint-agent definitions and configuration used by this deployment.

## Requirements

- Windows 10 / 11
- PowerShell 5.1 or PowerShell 7+ (ExecutionPolicy per-user `RemoteSigned`)
- PowerShell **Run as Administrator**
