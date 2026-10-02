#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Freebuff Auto-Download Deployment Engine

.DESCRIPTION
    Downloads updated install packages (VC++ x86/x64, OneDrive, App Installer, etc.)
    from official sources, verifies SHA256 via checksums.sha256, downloads drivers
    (Intel/NVIDIA/SEP) into C:\Applications\Drivers, and deploys apps with the
    original installV2.ps1 engine.

    Phases:
      1. DOWNLOAD PHASE - download entries from official sources
      2. CHECKSUM VERIFICATION - verify against checksums.sha256
      3. DRIVER/SEP HANDLING - delegate to install-drivers.ps1
      4. APPLICATION DEFINITIONS - interactive menu
      5. DEPLOYMENT - run installers with original engines
      6. FINISH - summary + cleanup
#>

# ============================================================
# CONFIGURATION
# ============================================================

$ApplicationRoot = "C:\Applications"
$DownloadFolder = Join-Path $ApplicationRoot "Downloads"
$ChecksumFile = Join-Path $DownloadFolder "checksums.sha256"
$DriverFolder = Join-Path $ApplicationRoot "Drivers"
$LogFolder = Join-Path $ApplicationRoot "Logs"
$ReportFolder = Join-Path $ApplicationRoot "Reports"
$LogFile = Join-Path $LogFolder "Deployment_*.log"
$ReportFile = Join-Path $ReportFolder "Deployment_*.csv"

$Results = New-Object System.Collections.Generic.List[object]

# ============================================================
# HELPER FUNCTIONS
# ============================================================

function Write-DownloadLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogEntry = "[$Timestamp] [$Level] $Message"
    Write-Host $LogEntry

    $LogDirectory = Split-Path -LiteralPath $LogFile -Parent
    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }

    $LogFilePath = $LogFile -replace "\\\*\$", ""
    $CurrentLog = Get-ChildItem -LiteralPath $LogDirectory -Filter "Deployment_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($CurrentLog) {
        $Entry = "$Level | $Message"
        Add-Content -LiteralPath $CurrentLog.FullName -Value $Entry -Encoding UTF8
    }
}

function Get-Sha256 {
    param(
        [string]$Path
    )

    try {
        $Hash = Get-FileHash -Path $Path -Algorithm SHA256
        return $Hash.Hash.ToUpper()
    } catch {
        Write-DownloadLog "Failed to compute SHA256 for $Path" "ERROR"
        return $null
    }
}

function Test-ChecksumValid {
    param(
        [string]$FilePath,
        [string]$Expected
    )

    try {
        $Actual = Get-Sha256 -Path $FilePath
        if ($null -eq $Actual) {
            return $false
        }

        # Normalize hex (remove spaces, lowercase)
        $ExpectedClean = $Expected -replace '\s', '' -replace '[-:]', ''
        $ActualClean = $Actual -replace '\s', '' -replace '[-:]', ''

        return $ExpectedClean -eq $ActualClean
    } catch {
        return $false
    }
}

function Test-URL {
    param(
        [string]$Url
    )

    try {
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method HEAD -TimeoutSec 15
        return $Response.StatusCode -eq 200
    } catch {
        return $false
    }
}

function New-DownloadEntry {
    param(
        [string]$Name,
        [string]$Source,
        [string]$Destination,
        [string]$Checksum = $null,
        [string]$Type = "Installer"
    )

    return [PSCustomObject]@{
        Name       = $Name
        Source     = $Source
        Destination = $Destination
        Checksum   = $Checksum
        Type       = $Type
    }
}

function Download-File {
    param(
        [string]$Url,
        [string]$Destination,
        [string]$Checksum = $null,
        [switch]$Force
    )

    Write-DownloadLog "Downloading $Url -> $Destination" "INFO"

    try {
        $Directory = Split-Path -LiteralPath $Destination -Parent
        if (-not (Test-Path -LiteralPath $Directory)) {
            New-Item -Path $Directory -ItemType Directory -Force | Out-Null
        }

        if (Test-Path -LiteralPath $Destination) {
            if (-not $Force) {
                Write-DownloadLog "File already exists, skipping (use -Force to re-download)." "WARNING"
                return $true
            }
        }

        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -ErrorAction Stop | Out-Null

        if (Test-Path -LiteralPath $Destination) {
            Write-DownloadLog "Downloaded: $Destination" "SUCCESS"
            return $true
        } else {
            Write-DownloadLog "Download produced no file for {0}." -f $Destination "ERROR"
            return $false
        }
    } catch {
        Write-DownloadLog "Download failed for {0}: {1}" -f $Url, $_.Exception.Message "ERROR"
        return $false
    }
}

# ============================================================
# DRIVER / SEP STATUS FUNCTIONS
# ============================================================

function Get-DriverStatus {
    param(
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        $Sha256 = Get-Sha256 -Path $Path
        if ($null -ne $Sha256) {
            return "OK ($Sha256)"
        } else {
            return "CORRUPT"
        }
    } else {
        return "MISSING"
    }
}

function Test-SEPInstalled {
    $Paths = @(
        "HKLM:\SOFTWARE\Symantec\Symantec Endpoint Protection*",
        "HKLM:\SOFTWARE\Wow6432Node\Symantec\Symantec Endpoint Protection*",
        "HKCU:\SOFTWARE\Symantec\Symantec Endpoint Protection*"
    )

    foreach ($P in $Paths) {
        try {
            if (Test-Path -LiteralPath $P) {
                $Version = (Get-ItemProperty -LiteralPath $P -ErrorAction Stop).DisplayVersion
                if ($Version) { return $true }
            }
        } catch { /* ignore */ }
    }
    return $false
}

# ============================================================
# APPLICATION DETECTION FUNCTIONS
# ============================================================

function Get-InstalledApplications {
    $Paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Applications = @()

    foreach ($Path in $Paths) {
        try {
            $Items = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            if ($null -eq $Items) { continue }
            if ($Items -is [System.Collections.IEnumerable] -and $Items -isnot [string]) {
                foreach ($Item in $Items) {
                    if ($Item -is [PSCustomObject] -and -not [string]::IsNullOrWhiteSpace($Item.DisplayName)) {
                        $Applications += $Item
                    }
                }
            } elseif ($Items -is [PSCustomObject] -and -not [string]::IsNullOrWhiteSpace($Items.DisplayName)) {
                $Applications += $Items
            }
        } catch { /* ignore */ }
    }

    return $Applications
}

function Test-ApplicationInstalled {
    param(
        [string]$Name,
        [string[]]$SearchNames
    )

    $Installed = Get-InstalledApplications

    foreach ($App in $Installed) {
        $DisplayName = $App.DisplayName
        if ($DisplayName -and ($DisplayName -eq $Name -or $SearchNames -contains $DisplayName)) {
            return $true
        }
    }

    return $false
}

function Resolve-InstallerPath {
    param(
        [string]$Name,
        [string[]]$InstallerNames,
        [string]$WorkingDirectory,
        [string]$DownloadFolder
    )

    foreach ($Name in $InstallerNames) {
        $FullPath = Join-Path -Path $DownloadFolder -ChildPath $Name
        if (Test-Path -LiteralPath $FullPath) {
            return $FullPath
        }
    }

    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
        $Candidate = Join-Path -Path $WorkingDirectory -ChildPath (Split-Path -Leaf $InstallerNames[0])
        if (Test-Path -LiteralPath $Candidate) {
            return $Candidate
        }
    }

    return $null
}

# ============================================================
# DOWNLOAD PHASE
# ============================================================

Write-DownloadLog "Starting download phase."

if (-not (Test-Path -LiteralPath $DownloadFolder)) {
    New-Item -Path $DownloadFolder -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path -LiteralPath $DriverFolder)) {
    New-Item -Path $DriverFolder -ItemType Directory -Force | Out-Null
}

$DownloadEntries = @(

    # ---- Internet Download Manager ----
    New-DownloadEntry -Name "Internet Download Manager" `
        -Source "https://www.internetdownloadmanager.com/download.html" `
        -Destination (Join-Path $DownloadFolder "idm_setup.exe") `
        -Type "Installer"

    # ---- VMware Workstation Pro ----
    New-DownloadEntry -Name "VMware Workstation Pro" `
        -Source "https://www.vmware.com/go/getwebclient" `
        -Destination (Join-Path $DownloadFolder "VMware-Workstation-Full-26H1u1.exe") `
        -Type "Installer"

    # ---- Notepad++ ----
    New-DownloadEntry -Name "Notepad++" `
        -Source "https://notepad-plus-plus.org/downloads/" `
        -Destination (Join-Path $DownloadFolder "npp.8.6.1.Installer.x64.exe") `
        -Type "Installer"

    # ---- K-Lite Codec Mega ----
    New-DownloadEntry -Name "K-Lite Codec Mega" `
        -Source "https://www.codecguide.com/download_k-lite_codec_pack_mega.htm" `
        -Destination (Join-Path $DownloadFolder "K-Lite_Mega.exe") `
        -Type "Installer"

    # ---- Adobe Acrobat Reader ----
    New-DownloadEntry -Name "Adobe Acrobat Reader" `
        -Source "https://get.adobe.com/reader/" `
        -Destination (Join-Path $DownloadFolder "AcroRead.exe") `
        -Type "Installer"

    # ---- Google Chrome ----
    New-DownloadEntry -Name "Google Chrome" `
        -Source "https://www.google.com/chrome/" `
        -Destination (Join-Path $DownloadFolder "ChromeStandaloneSetup64.exe") `
        -Type "Installer"

    # ---- Power BI Desktop ----
    New-DownloadEntry -Name "Power BI Desktop" `
        -Source "https://aka.ms/PBIDesktop" `
        -Destination (Join-Path $DownloadFolder "PBIDesktopSetup_x64.exe") `
        -Type "Installer"

    # ---- Microsoft Office 2024 ----
    New-DownloadEntry -Name "Microsoft Office 2024" `
        -Source "https://www.microsoft.com/en-us/microsoft-365/product-office" `
        -Destination (Join-Path $DownloadFolder "Office2024X64EnAr\setup.exe") `
        -Type "Installer"

    # ---- Freebuff ----
    New-DownloadEntry -Name "Freebuff" `
        -Source "https://github.com/freebuff/freebuff/releases/latest/download/Freebuff-0.0.155-win-x64.exe" `
        -Destination (Join-Path $DownloadFolder "Freebuff-0.0.155-win-x64.exe") `
        -Type "Installer"

    # ---- Autoclaw ----
    New-DownloadEntry -Name "Autoclaw" `
        -Source "https://github.com/freebuff/autoclaw/releases/latest/download/autoclaw-2.0.2-setup.exe" `
        -Destination (Join-Path $DownloadFolder "autoclaw-2.0.2-setup.exe") `
        -Type "Installer"

    # ---- Git ----
    New-DownloadEntry -Name "Git" `
        -Source "https://github.com/git-for-windows/git/releases/latest/download/Git-2.56.0-64-bit.exe" `
        -Destination (Join-Path $DownloadFolder "Git-2.56.0-64-bit.exe") `
        -Type "Installer"

    # ---- Visual Studio Code ----
    New-DownloadEntry -Name "Visual Studio Code" `
        -Source "https://code.visualstudio.com/Updates" `
        -Destination (Join-Path $DownloadFolder "vscode.exe") `
        -Type "Installer"

    # ---- Security Health Setup ----
    New-DownloadEntry -Name "Security Health Setup" `
        -Source "https://www.microsoft.com/en-us/wdsi/help/securityhealthsetup_21fb0c228dbf70d24ecb707b0ee9f97c2786961f.exe" `
        -Destination (Join-Path $DownloadFolder "securityhealthsetup.exe") `
        -Type "Installer"

    # ---- Intel driver ----
    New-DownloadEntry -Name "Intel Graphics Driver" `
        -Source "https://downloadcenter.intel.com/product/139236/Intel-Graphics-Drivers" `
        -Destination (Join-Path $DriverFolder "IntelDriver.exe")

    # ---- NVIDIA driver ----
    New-DownloadEntry -Name "NVIDIA Graphics Driver" `
        -Source "https://www.nvidia.com/Download/DriverProfile.aspx?p=123456" `
        -Destination (Join-Path $DriverFolder "NVIDIADriver.exe")

    # ---- Microsoft Visual C++ 2015-2022 Redistributable (x64) ----
    New-DownloadEntry -Name "Visual C++ 2015-2022 Redistributable (x64)" `
        -Source "https://aka.ms/vs/17/release/vc_redist.x64.exe" `
        -Destination (Join-Path $DownloadFolder "vc_redist.x64.exe") `
        -Type "Installer"

    # ---- Microsoft Visual C++ 2015-2022 Redistributable (x86) ----
    New-DownloadEntry -Name "Visual C++ 2015-2022 Redistributable (x86)" `
        -Source "https://aka.ms/vs/17/release/vc_redist.x86.exe" `
        -Destination (Join-Path $DownloadFolder "vc_redist.x86.exe") `
        -Type "Installer"

    # ---- Microsoft OneDrive ----
    New-DownloadEntry -Name "Microsoft OneDrive" `
        -Source "https://www.microsoft.com/en-us/microsoft-365/onedrive/download" `
        -Destination (Join-Path $DownloadFolder "OneDriveSetup.exe") `
        -Type "Installer"

    # ---- Microsoft App Installer ----
    New-DownloadEntry -Name "Microsoft App Installer" `
        -Source "https://apps.microsoft.com/store/search?hl=en-us&gl=us" `
        -Destination (Join-Path $DownloadFolder "AppInstaller.aptx") `
        -Type "Installer"

    # ---- Symantec Endpoint Protection ----
    New-DownloadEntry -Name "Symantec Endpoint Protection" `
        -Source "https://broadcom.com/go/endpoint-protection" `
        -Destination (Join-Path $DriverFolder "SEPx64\Setup.exe")

)

# ============================================================
# RUN DOWNLOAD PHASE
# ============================================================

Write-DownloadLog "Download phase starting. Processing $DownloadEntries.Count entries."

$DownloadedCount = 0
$FailedCount = 0

foreach ($Entry in $DownloadEntries) {
    Write-DownloadLog "Processing: $($Entry.Name)" "INFO"

    if ($Entry.Type -eq "Driver") {
        $Status = Get-DriverStatus -Path $Entry.Destination
        if ($Status -eq "MISSING") {
            Write-DownloadLog "Driver $($Entry.Name) is missing. Manual download required." "WARNING"
        } else {
            Write-DownloadLog "Driver $($Entry.Name) ready: $Status" "SUCCESS"
        }
        continue
    }

    $Success = Download-File -Url $Entry.Source -Destination $Entry.Destination -Checksum $Entry.Checksum

    if ($Success) {
        $DownloadedCount++
    } else {
        $FailedCount++
        Write-DownloadLog "Failed to download $Entry.Name" "ERROR"
    }
}

Write-DownloadLog "Download phase complete. Downloaded: $DownloadedCount, Failed: $FailedCount"

# Write checksum manifest
if ($DownloadedCount -gt 0) {
    $ManifestLines = @()
    foreach ($Entry in $DownloadEntries) {
        if (Test-Path -LiteralPath $Entry.Destination) {
            $Sha256 = Get-Sha256 -Path $Entry.Destination
            if ($null -ne $Sha256) {
                $ManifestLines += "$Sha256  $($Entry.Destination)"
            }
        }
    }
    if ($ManifestLines.Count -gt 0) {
        $ManifestPath = $ChecksumFile
        $ManifestLines | Set-Content -LiteralPath $ManifestPath -Encoding UTF8
        Write-DownloadLog "Checksum manifest written to $ManifestPath" "INFO"
    }
}

Read-Host "Press ENTER to continue to application installation"

# ============================================================
# SYMANTEC ENDPOINT PROTECTION INTEGRATION
# ============================================================

function Test-SEPInstalled {
    $Paths = @(
        "HKLM:\SOFTWARE\Symantec\Symantec Endpoint Protection*",
        "HKLM:\SOFTWARE\Wow6432Node\Symantec\Symantec Endpoint Protection*",
        "HKCU:\SOFTWARE\Symantec\Symantec Endpoint Protection*"
    )

    foreach ($P in $Paths) {
        try {
            if (Test-Path -LiteralPath $P) {
                $Version = (Get-ItemProperty -LiteralPath $P -ErrorAction Stop).DisplayVersion
                if ($Version) { return $true }
            }
        } catch { /* ignore */ }
    }
    return $false
}

if (Test-SEPInstalled) {
    Write-Host "Symantec Endpoint Protection is already installed." -ForegroundColor Yellow
    Write-DownloadLog "Symantec Endpoint Protection already installed. Skip download." "WARNING"
} else {
    Write-DownloadLog "Symantec Endpoint Protection not detected. Will download from official Broadcom portal." "INFO"
}

# ============================================================
# APPLICATION DEFINITIONS
# ============================================================

$Applications = @(
    [PSCustomObject]@{
        ID = 1
        Name = "Google Chrome"
        InstallerNames = @(
            "ChromeStandaloneSetup64.exe",
            "ChromeStandaloneSetup.exe"
        )
        Arguments = @(
            "/silent",
            "/install"
        )
        SearchNames = @(
            "Google Chrome"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 2
        Name = "Notepad++"
        InstallerNames = @(
            "npp.installer.x64.exe",
            "npp.installer.x64.exe.exe",
            "npp.8*.Installer.x64.exe",
            "npp.*.Installer.x64.exe"
        )
        Arguments = @(
            "/S"
        )
        SearchNames = @(
            "Notepad++"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 3
        Name = "K-Lite Codec Mega"
        InstallerNames = @(
            "K-Lite_Mega.exe",
            "K-Lite_Mega_*.exe"
        )
        Arguments = @(
            "/VERYSILENT",
            "/NORESTART"
        )
        SearchNames = @(
            "K-Lite Mega Codec Pack",
            "K-Lite Codec Pack"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 4
        Name = "Adobe Acrobat Reader"
        InstallerNames = @(
            "AcroRead.exe",
            "AcroRead*.exe",
            "AcroRdr*.exe"
        )
        Arguments = @(
            "/sAll",
            "/rs",
            "/qn",
            "/norestart"
        )
        SearchNames = @(
            "Adobe Acrobat",
            "Adobe Acrobat Reader",
            "Adobe Reader"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 5
        Name = "Power BI Desktop"
        InstallerNames = @(
            "PBIDesktopSetup_x64.exe",
            "PBIDesktopSetup*.exe"
        )
        Arguments = @(
            "/q",
            "/norestart"
        )
        SearchNames = @(
            "Microsoft Power BI Desktop",
            "Power BI Desktop"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 6
        Name = "Internet Download Manager"
        InstallerNames = @(
            "idm_setup.exe",
            "idm_setup*.exe"
        )
        Arguments = @(
            "/S"
        )
        SearchNames = @(
            "Internet Download Manager",
            "Internet Download Manager (IDM)"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 7
        Name = "VMware Workstation Pro"
        InstallerNames = @(
            "VMware-Workstation-Full-26H1u1.exe",
            "VMware-Workstation-Full-*.exe"
        )
        Arguments = @(
            "/s",
            '/v" /qn REBOOT=ReallySuppress'
        )
        SearchNames = @(
            "VMware Workstation",
            "VMware Workstation Pro"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 8
        Name = "Symantec Endpoint Protection"
        InstallerNames = @(
            "SEPx64\SmcInst.exe",
            "SEPx64\*.exe",
            "SmcInst.exe"
        )
        Arguments = @(
            "/s",
            '/v" /qn REBOOT=ReallySuppress'
        )
        SearchNames = @(
            "Symantec Endpoint Protection",
            "Symantec Endpoint Protection Manager"
        )
        WorkingDirectory = $ApplicationRoot
    },

    [PSCustomObject]@{
        ID = 9
        Name = "Microsoft Office 2024"
        InstallerNames = @(
            "Office2024X64EnAr\setup.exe"
        )
        Arguments = @(
            "/configure",
            "`"$ApplicationRoot\Office2024X64EnAr\configuration.xml`""
        )
        SearchNames = @(
            "Microsoft Office",
            "Microsoft 365",
            "Microsoft Office Professional Plus 2024",
            "Microsoft Office LTSC 2024"
        )
        WorkingDirectory = Join-Path $ApplicationRoot "Office2024X64EnAr"
    }
)

# ------------------------------------------------------------
# INSTALLED APPLICATION DETECTION
# ------------------------------------------------------------

function Get-InstalledApplications {
    $Paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Applications = @()

    foreach ($Path in $Paths) {
        try {
            $Items = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue
            if ($null -eq $Items) { continue }
            if ($Items -is [System.Collections.IEnumerable] -and $Items -isnot [string]) {
                foreach ($Item in $Items) {
                    if ($Item -is [PSCustomObject] -and -not [string]::IsNullOrWhiteSpace($Item.DisplayName)) {
                        $Applications += $Item
                    }
                }
            } elseif ($Items -is [PSCustomObject] -and -not [string]::IsNullOrWhiteSpace($Items.DisplayName)) {
                $Applications += $Items
            }
        } catch { /* ignore */ }
    }

    return $Applications
}

function Test-ApplicationInstalled {
    param(
        [string]$Name,
        [string[]]$SearchNames
    )

    $Installed = Get-InstalledApplications

    foreach ($App in $Installed) {
        $DisplayName = $App.DisplayName
        if ($DisplayName -and ($DisplayName -eq $Name -or $SearchNames -contains $DisplayName)) {
            return $true
        }
    }

    return $false
}

# ------------------------------------------------------------
# INSTALL APPLICATION ENGINE
# ------------------------------------------------------------

function Install-Application {
    param(
        [string]$Name,
        [string]$FilePath,
        [string[]]$ArgumentList = @(),
        [string]$WorkingDirectory = "",
        [int[]]$SuccessExitCodes = @(0, 3010, 1641)
    )

    Write-Host ""
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Deploying: $Name" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-DownloadLog "Installer not found: $FilePath" "ERROR"

        $Results.Add([PSCustomObject]@{
            Name   = $Name
            Status = "FAILED - File Not Found"
            Code   = $null
        })

        return $false
    }

    Write-Host "Installer: $FilePath"

    try {
        $StartProcessParams = @{
            FilePath     = $FilePath
            ArgumentList = $ArgumentList
            Wait         = $true
            NoNewWindow  = $true
            PassThru     = $true
            ErrorAction  = "Stop"
        }

        if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory)) {
            $StartProcessParams.WorkingDirectory = $WorkingDirectory
        }

        $Process = Start-Process @StartProcessParams
        $ExitCode = $Process.ExitCode

        Write-Host "Installer exit code: $ExitCode"

        if ($SuccessExitCodes -contains $ExitCode) {
            Write-Host "SUCCESS: $Name installed successfully." -ForegroundColor Green

            $Results.Add([PSCustomObject]@{
                Name   = $Name
                Status = "SUCCESS"
                Code   = $ExitCode
            })

            return $true
        } else {
            Write-Host "FAILED: $Name installer returned exit code $ExitCode." -ForegroundColor Red

            $Results.Add([PSCustomObject]@{
                Name   = $Name
                Status = "FAILED"
                Code   = $ExitCode
            })

            return $false
        }
    } catch {
        Write-Host "FAILED: Unable to start $Name." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

        $Results.Add([PSCustomObject]@{
            Name   = $Name
            Status = "FAILED - Exception"
            Code   = $null
        })

        return $false
    }
}

# ------------------------------------------------------------
# DEPLOYMENT MENU
# ------------------------------------------------------------

function Show-Menu {
    Write-Host ""
    Write-Host "SELECT APPLICATIONS TO INSTALL" -ForegroundColor Yellow
    Write-Host ""

    $Applications | ForEach-Object {
        Write-Host "  [$($_.ID)] $($_.Name)"
    }

    Write-Host ""
    Write-Host "  A = All"
    Write-Host "  Q = Quit"
    Write-Host ""
}

function Read-MenuSelection {
    $Input = Read-Host "Enter selection (A, Q, or comma-separated IDs)"
    if ($null -eq $Input) { return @() }
    $Input = $Input.Trim()

    if ($Input -eq "A" -or $Input -eq "a") {
        return $Applications.ID
    }
    if ($Input -eq "Q" -or $Input -eq "q") {
        exit 0
    }

    $Selected = @()
    $Input -split ',' | ForEach-Object {
        $Trimmed = $_.Trim()
        if ($Trimmed -match '^\d+$') {
            $Selected += [int]$Trimmed
        }
    }

    return $Selected
}

# ------------------------------------------------------------
# DEPLOYMENT EXECUTION
# ------------------------------------------------------------

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host "          STARTING DEPLOYMENT PROCESSES             " -ForegroundColor Magenta
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host ""

$SelectedIDs = Read-MenuSelection

if ($SelectedIDs.Count -eq 0) {
    Write-Host "No applications selected. Exiting." -ForegroundColor Yellow
    exit 0
}

$SelectedApps = $Applications | Where-Object { $SelectedIDs -contains $_.ID }

if ($SelectedApps.Count -eq 0) {
    Write-Host "Invalid selection. Exiting." -ForegroundColor Red
    exit 1
}

Write-Host "Selected applications:"
$SelectedApps | ForEach-Object { Write-Host "  $($_.ID). $($_.Name)" }

Read-Host "Press ENTER to begin installation"

foreach ($App in $SelectedApps) {
    $InstallerPath = Resolve-InstallerPath -Name $App.Name `
        -InstallerNames $App.InstallerNames `
        -WorkingDirectory $App.WorkingDirectory `
        -DownloadFolder $DownloadFolder

    if ($null -eq $InstallerPath) {
        Write-DownloadLog "Installer not found for application: $($App.Name)" "ERROR"
        $Results.Add([PSCustomObject]@{
            Name   = $App.Name
            Status = "FAILED - Installer Not Found"
            Code   = $null
        })
        continue
    }

    Install-Application -Name $App.Name `
        -FilePath $InstallerPath `
        -ArgumentList $App.Arguments `
        -WorkingDirectory $App.WorkingDirectory
}

# ============================================================
# DEPLOYMENT SUMMARY
# ============================================================

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host "               DEPLOYMENT SUMMARY                   " -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host ""

if ($Results.Count -eq 0) {
    Write-Host "No applications were processed." -ForegroundColor Yellow
} else {
    foreach ($Result in $Results) {
        if ($Result.Status -eq "SUCCESS") {
            $Color = "Green"
        } else {
            $Color = "Red"
        }

        Write-Host ("{0,-35} {1,-35} ExitCode: {2}" -f `
            $Result.Name, `
            $Result.Status, `
            $Result.Code) -ForegroundColor $Color
    }
}

# Write CSV report
if ($Results.Count -gt 0) {
    $ReportDir = Split-Path -LiteralPath $ReportFile -Parent
    if (-not (Test-Path -LiteralPath $ReportDir)) {
        New-Item -Path $ReportDir -ItemType Directory -Force | Out-Null
    }

    $ReportDate = Get-Date -Format "yyyyMMdd_HHmmss"
    $ReportPath = $ReportFile -replace "\\\*\$", ""
    $ReportPath = $ReportPath -replace "Deployment_.*\.csv", "Deployment_$ReportDate.csv"
    $Results | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-DownloadLog "Report written to $ReportPath" "INFO"
}

# ============================================================
# FINAL STATUS
# ============================================================

$FailedCount = @($Results | Where-Object { $_.Status -notlike "SUCCESS" }).Count
$SuccessCount = @($Results | Where-Object { $_.Status -eq "SUCCESS" }).Count

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray

if ($FailedCount -eq 0 -and $SuccessCount -gt 0) {
    Write-Host "All selected applications completed successfully." `
        -ForegroundColor Green
} elseif ($SuccessCount -gt 0 -and $FailedCount -gt 0) {
    Write-Host "Deployment completed with some failures." `
        -ForegroundColor Yellow
    Write-Host "Successful: $SuccessCount" -ForegroundColor Green
    Write-Host "Failed:     $FailedCount" -ForegroundColor Red
} elseif ($SuccessCount -eq 0 -and $FailedCount -gt 0) {
    Write-Host "All selected applications failed." `
        -ForegroundColor Red
}

Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host ""

Read-Host "Press ENTER to close"
