<#
.SYNOPSIS
    Scans for and installs missing Windows updates with logging and error handling.
.DESCRIPTION
    - Ensures NuGet and PSWindowsUpdate are available.
    - Scans for available updates.
    - Installs updates with optional reboot.
    - Logs any errors to a local file.
.NOTES
    Author: [Your Name]
    Modified: [Date]
    Log: C:\WindowsUpdateErrorLog.txt
#>

# Global error log path
$logPath = "C:\WindowsUpdateErrorLog.txt"

# Function to handle and log errors
function Handle-Error {
    param (
        [string]$ErrorMessage
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
    Add-Content -Path $logPath -Value "$timestamp - $ErrorMessage"
}

# Ensure NuGet provider is installed and current
function Update-NuGetProvider {
    try {
        Write-Host "Checking NuGet provider..." -ForegroundColor Cyan
        $nuGet = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue

        if (-not $nuGet) {
            Write-Host "Installing NuGet provider..." -ForegroundColor Cyan
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
        } else {
            Write-Host "Updating NuGet provider..." -ForegroundColor Cyan
            Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
        }
    } catch {
        Handle-Error "Failed to install/update NuGet provider: $_"
    }
}

# Ensure PSWindowsUpdate module is available
function Ensure-WindowsUpdateModule {
    try {
        if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
            Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan
            Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck -ErrorAction Stop
        }
        Import-Module PSWindowsUpdate -ErrorAction Stop
        Write-Host "PSWindowsUpdate module imported." -ForegroundColor Green
    } catch {
        Handle-Error "Failed to install or import PSWindowsUpdate: $_"
    }
}

# Scan for missing updates
function Check-For-Updates {
    try {
        Write-Host "Scanning for Windows updates..." -ForegroundColor Cyan
        $updates = Get-WindowsUpdate -AcceptAll -MicrosoftUpdate -ErrorAction Stop
        if ($updates.Count -eq 0) {
            Write-Host "No missing updates found." -ForegroundColor Green
            return $null
        } else {
            Write-Host "Found $($updates.Count) update(s) to install." -ForegroundColor Yellow
            return $updates
        }
    } catch {
        Handle-Error "Failed to check for updates: $_"
        return $null
    }
}

# Install updates and reboot if needed
function Install-Updates {
    param (
        [Parameter(Mandatory = $true)]
        [array]$UpdatesToInstall
    )

    try {
        Write-Host "Installing updates..." -ForegroundColor Cyan
        foreach ($update in $UpdatesToInstall) {
            Write-Host "Installing: $($update.Title) [$($update.KBArticleIDs)]" -ForegroundColor Yellow
            Install-WindowsUpdate -KBArticleID $update.KBArticleIDs -AcceptAll -AutoReboot -ErrorAction Stop
        }
        Write-Host "All updates installed." -ForegroundColor Green
    } catch {
        Handle-Error "Failed during update installation: $_"
    }
}

# MAIN SCRIPT
try {
    Update-NuGetProvider
    Ensure-WindowsUpdateModule
    $updates = Check-For-Updates

    if ($updates) {
        Install-Updates -UpdatesToInstall $updates
    }
} catch {
    Handle-Error "Unexpected error during update process: $_"
}
