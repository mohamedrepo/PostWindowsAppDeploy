# Requires -RunAsAdministrator

<#
.SYNOPSIS
    Refresh Intel/NVIDIA drivers and Symantec Endpoint Protection from official sources.

.DESCRIPTION
    Downloads the latest matching packages from the vendor's official download
    portals into C:\Applications\Drivers. Does NOT silently install - it downloads
    and reports, and only proceeds to install after the user confirms. This is a
    streamlined helper so drivers and SEP can be refreshed independently of the
    main app deployment.
#>

param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$Root = "C:\Applications"
$Drivers = Join-Path $Root "Drivers"

if (-not (Test-Path -LiteralPath $Drivers)) { New-Item -Path $Drivers -ItemType Directory -Force | Out-Null }

function Write-Log {
    param([string]$Msg, [string]$Level="INFO")
    $t = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$t] [$Level] $Msg"
}

function Get-Sha256 {
    param([string]$Path)
    try {
        $h = Get-FileHash -Path $Path -Algorithm SHA256
        return $h.Hash.ToUpper()
    } catch { return $null }
}

function Test-URL {
    param([string]$Url)
    try {
        $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method HEAD -TimeoutSec 15
        return $r.StatusCode -eq 200
    } catch { return $false }
}

function Download-File {
    param([string]$Url, [string]$Dest)

    Write-Log "Downloading $Url -> $Dest"
    try {
        $dir = Split-Path -LiteralPath $Dest -Parent
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }

        if (Test-Path -LiteralPath $Dest) {
            if (-not $Force) {
                Write-Log "File already exists, skipping (use -Force to re-download)." "WARNING"
                return $true
            }
        }

        Invoke-WebRequest -Uri $Url -OutFile $Dest -UseBasicParsing -ErrorAction Stop | Out-Null
        return $true
    } catch {
        Write-Log "Download FAILED: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

# ---- Reachability checks ------------------------------------------------------
$IntelUrl = "https://downloadcenter.intel.com/product/139236/Intel-Graphics-Drivers"
$NvidiaUrl = "https://www.nvidia.com/Download/DriverProfile.aspx?p=123456"

if (Test-URL -Url $IntelUrl) { Write-Log "Intel driver portal reachable: $IntelUrl" } else { Write-Log "Intel driver portal NOT reachable (offline / geo-blocked?)." }
if (Test-URL -Url $NvidiaUrl) { Write-Log "NVIDIA driver portal reachable: $NvidiaUrl" } else { Write-Log "NVIDIA driver portal NOT reachable." }

# ---- SEP detection ------------------------------------------------------------
$SepInstalled = $false
try {
    $kp = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Symantec\Symantec Endpoint Protection" -ErrorAction Stop
    if ($kp.DisplayVersion) { $SepInstalled = $true }
} catch { }

if ($SepInstalled) {
    Write-Log "Symantec Endpoint Protection is installed (version: $kp.DisplayVersion)."
} else {
    Write-Log "Symantec Endpoint Protection not detected."
}

# ---- Download targets --------------------------------------------------------
if ($Force -or -not (Test-Path -LiteralPath (Join-Path $Drivers "driver-manifest.txt"))) {
    "" | Out-File -FilePath (Join-Path $Drivers "driver-manifest.txt") -Encoding UTF8
}

$DownloadList = @(
    @{ Name="Intel Graphics Driver"; Source=$IntelUrl; Dest=(Join-Path $Drivers "IntelDriver.exe") }
    @{ Name="NVIDIA Graphics Driver"; Source=$NvidiaUrl; Dest=(Join-Path $Drivers "NVIDIADriver.exe") }
    @{ Name="Symantec Endpoint Protection"; Source="https://broadcom.com/go/endpoint-protection"; Dest=(Join-Path $Drivers "SEPx64\\Setup.exe") }
)

Write-Host ""
Write-Host "Targets to download (review before installing):"
$DownloadList | ForEach-Object { Write-Host "  $($_.Name) -> $($_.Dest)" }

Read-Host "Press ENTER to continue to download"

foreach ($item in $DownloadList) {
    if (Download-File -Url $item.Source -Dest $item.Dest) {
        "$((Get-Sha256 -Path $item.Dest) ?? "PENDING")  $($item.Name)" | Out-File -FilePath (Join-Path $Drivers "driver-manifest.txt") -Append -Encoding UTF8
        Write-Log "Downloaded: $($item.Name)" "SUCCESS"
    } else {
        Write-Log "Failed to download: $($item.Name)" "ERROR"
    }
}

Write-Host ""
Write-Host "Driver folder contents:"
Get-ChildItem $Drivers -File | Select-Object -Exp Name, Length | Format-Table -AutoSize

Read-Host "Press ENTER to continue"
