#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Windows 11 Application Deployment Script

.DESCRIPTION
    Select applications interactively and install them from:
    C:\Applications

.NOTES
    Run PowerShell as Administrator.
#>

# ============================================================
# Configuration
# ============================================================

$InstallerFolder = "C:\Applications"

# ============================================================
# Helper Functions
# ============================================================

function Write-Banner {
    Clear-Host

    Write-Host "====================================================" -ForegroundColor DarkGray
    Write-Host "        WINDOWS 11 APPLICATION DEPLOYMENT           " -ForegroundColor Yellow
    Write-Host "====================================================" -ForegroundColor DarkGray
    Write-Host ""
}

function Ask-YesNo {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Question
    )

    do {
        $Answer = Read-Host "$Question (Y/N)"
    }
    while ($Answer -notmatch '^[YyNn]$')

    return ($Answer -match '^[Yy]$')
}

function Install-Application {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [string[]]$ArgumentList = @(),

        [string]$WorkingDirectory = "",

        [int[]]$SuccessExitCodes = @(0)
    )

    Write-Host ""
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "Deploying: $Name" -ForegroundColor Cyan
    Write-Host "----------------------------------------------------" -ForegroundColor DarkGray

    # Check installer exists
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        Write-Host "FAILED: Installer not found:" -ForegroundColor Red
        Write-Host "       $FilePath" -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = $Name
            Status = "FAILED - File Not Found"
            Code   = $null
        }
    }

    Write-Host "Installer: $FilePath" -ForegroundColor Gray

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

        Write-Host "Installer exit code: $ExitCode" -ForegroundColor Gray

        if ($SuccessExitCodes -contains $ExitCode) {
            Write-Host "SUCCESS: $Name installed successfully." -ForegroundColor Green

            return [PSCustomObject]@{
                Name   = $Name
                Status = "SUCCESS"
                Code   = $ExitCode
            }
        }
        else {
            Write-Host "FAILED: $Name installer returned exit code $ExitCode." -ForegroundColor Red

            return [PSCustomObject]@{
                Name   = $Name
                Status = "FAILED"
                Code   = $ExitCode
            }
        }
    }
    catch {
        Write-Host "FAILED: Unable to start $Name." -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red

        return [PSCustomObject]@{
            Name   = $Name
            Status = "FAILED - Exception"
            Code   = $null
        }
    }
}

# ============================================================
# Initial Checks
# ============================================================

Write-Banner

Write-Host "Checking deployment folder..." -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $InstallerFolder)) {
    Write-Host "C:\Applications does not exist." -ForegroundColor Yellow
    Write-Host "Creating folder..." -ForegroundColor Yellow

    try {
        New-Item -Path $InstallerFolder -ItemType Directory -Force -ErrorAction Stop | Out-Null
        Write-Host "Folder created successfully." -ForegroundColor Green
    }
    catch {
        Write-Host "Unable to create $InstallerFolder" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Red
        exit 1
    }
}

Write-Host "Installer folder: $InstallerFolder" -ForegroundColor Gray
Write-Host ""

# ============================================================
# Application Selection
# ============================================================

Write-Host "SELECT PROGRAMS TO INSTALL" -ForegroundColor Yellow
Write-Host ""

$InstallChrome = Ask-YesNo "Do you want to install Google Chrome?"
$InstallNpp    = Ask-YesNo "Do you want to install Notepad++?"
$InstallKlite  = Ask-YesNo "Do you want to install K-Lite Codec Mega?"
$InstallAdobe  = Ask-YesNo "Do you want to install Adobe Acrobat Reader?"
$InstallPbi    = Ask-YesNo "Do you want to install Power BI Desktop?"
$InstallIdm    = Ask-YesNo "Do you want to install Internet Download Manager?"
$InstallVmware = Ask-YesNo "Do you want to install VMware Workstation Pro?"
$InstallSep    = Ask-YesNo "Do you want to install Symantec Endpoint Protection?"
$InstallOffice = Ask-YesNo "Do you want to install Microsoft Office 2024?"

# ============================================================
# Deployment
# ============================================================

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host "          STARTING DEPLOYMENT PROCESSES             " -ForegroundColor Magenta
Write-Host "====================================================" -ForegroundColor DarkGray

$Results = @()

# ============================================================
# 1. Google Chrome
# ============================================================

if ($InstallChrome) {

    $File = Join-Path $InstallerFolder "ChromeStandaloneSetup64.exe"

    $Results += Install-Application `
        -Name "Google Chrome" `
        -FilePath $File `
        -ArgumentList @("/silent", "/install")
}

# ============================================================
# 2. Notepad++
# ============================================================

if ($InstallNpp) {

    # IMPORTANT:
    # Your original script had:
    # npp.installer.x64.exe.exe
    #
    # This looks like a duplicated .exe extension.
    #
    # Change this filename if your actual file is different.

    $File = Join-Path $InstallerFolder "npp.installer.x64.exe"

    $Results += Install-Application `
        -Name "Notepad++" `
        -FilePath $File `
        -ArgumentList @("/S")
}

# ============================================================
# 3. K-Lite Codec Mega
# ============================================================

if ($InstallKlite) {

    $File = Join-Path $InstallerFolder "K-Lite_Mega.exe"

    $Results += Install-Application `
        -Name "K-Lite Codec Mega" `
        -FilePath $File `
        -ArgumentList @("/VERYSILENT", "/NORESTART")
}

# ============================================================
# 4. Adobe Acrobat Reader
# ============================================================

if ($InstallAdobe) {

    $File = Join-Path $InstallerFolder "AcroRead.exe"

    $Results += Install-Application `
        -Name "Adobe Acrobat Reader" `
        -FilePath $File `
        -ArgumentList @("/sAll", "/rs", "/qn", "/norestart")
}

# ============================================================
# 5. Power BI Desktop
# ============================================================

if ($InstallPbi) {

    $File = Join-Path $InstallerFolder "PBIDesktopSetup_x64.exe"

    $Results += Install-Application `
        -Name "Power BI Desktop" `
        -FilePath $File `
        -ArgumentList @("/q", "/norestart")
}

# ============================================================
# 6. Internet Download Manager
# ============================================================

if ($InstallIdm) {

    $File = Join-Path $InstallerFolder "idm_setup.exe"

    $Results += Install-Application `
        -Name "Internet Download Manager" `
        -FilePath $File `
        -ArgumentList @("/S")
}

# ============================================================
# 7. VMware Workstation Pro
# ============================================================

if ($InstallVmware) {

    $File = Join-Path $InstallerFolder "VMware-Workstation-Full-26H1u1.exe"

    $Results += Install-Application `
        -Name "VMware Workstation Pro" `
        -FilePath $File `
        -ArgumentList @(
            "/s",
            '/v/qn REBOOT=ReallySuppress'
        )
}

# ============================================================
# 8. Symantec Endpoint Protection
# ============================================================

if ($InstallSep) {

    $File = Join-Path $InstallerFolder "SEPx64\SmcInst.exe"

    $Results += Install-Application `
        -Name "Symantec Endpoint Protection" `
        -FilePath $File `
        -ArgumentList @(
            "/s",
            '/v/qn REBOOT=ReallySuppress'
        )
}

# ============================================================
# 9. Microsoft Office 2024
# ============================================================

if ($InstallOffice) {

    $OfficeFolder = Join-Path $InstallerFolder "Office2024X64EnAr"
    $File          = Join-Path $OfficeFolder "setup.exe"
    $XmlPath       = Join-Path $OfficeFolder "configuration.xml"

    if (-not (Test-Path -LiteralPath $XmlPath -PathType Leaf)) {

        Write-Host ""
        Write-Host "FAILED: Office configuration file not found:" -ForegroundColor Red
        Write-Host "       $XmlPath" -ForegroundColor Red

        $Results += [PSCustomObject]@{
            Name   = "Microsoft Office 2024"
            Status = "FAILED - Configuration File Not Found"
            Code   = $null
        }
    }
    else {

        $Results += Install-Application `
            -Name "Microsoft Office 2024" `
            -FilePath $File `
            -ArgumentList @(
                "/configure",
                "`"$XmlPath`""
            ) `
            -WorkingDirectory $OfficeFolder
    }
}

# ============================================================
# Deployment Summary
# ============================================================

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host "               DEPLOYMENT SUMMARY                   " -ForegroundColor Yellow
Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host ""

if ($Results.Count -eq 0) {

    Write-Host "No applications were selected." -ForegroundColor Yellow
}
else {

    foreach ($Result in $Results) {

        if ($Result.Status -eq "SUCCESS") {
            $Color = "Green"
        }
        else {
            $Color = "Red"
        }

        Write-Host ("{0,-35} {1,-35} ExitCode: {2}" -f `
            $Result.Name, `
            $Result.Status, `
            $Result.Code) -ForegroundColor $Color
    }
}

# ============================================================
# Final Status
# ============================================================

$FailedCount = @(
    $Results | Where-Object {
        $_.Status -notlike "SUCCESS"
    }
).Count

$SuccessCount = @(
    $Results | Where-Object {
        $_.Status -eq "SUCCESS"
    }
).Count

Write-Host ""
Write-Host "====================================================" -ForegroundColor DarkGray

if ($FailedCount -eq 0 -and $SuccessCount -gt 0) {

    Write-Host "All selected applications completed successfully." `
        -ForegroundColor Green
}
elseif ($SuccessCount -gt 0 -and $FailedCount -gt 0) {

    Write-Host "Deployment completed with some failures." `
        -ForegroundColor Yellow

    Write-Host "Successful: $SuccessCount" -ForegroundColor Green
    Write-Host "Failed:     $FailedCount" -ForegroundColor Red
}
elseif ($SuccessCount -eq 0 -and $FailedCount -gt 0) {

    Write-Host "All selected applications failed." `
        -ForegroundColor Red
}

Write-Host "====================================================" -ForegroundColor DarkGray
Write-Host ""

Read-Host "Press ENTER to exit"