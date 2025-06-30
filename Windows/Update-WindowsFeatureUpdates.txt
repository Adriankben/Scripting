<#
.SYNOPSIS
    Automates checking for and installing Windows feature updates using PSWindowsUpdate.
.DESCRIPTION
    - Ensures NuGet and PSWindowsUpdate modules are installed
    - Imports necessary modules
    - Scans for Windows Feature Updates
    - Attempts installation and logs errors
.NOTES
    Author: [Your Name]
    Last Updated: [Date]
    Log file: C:\WindowsUpdateErrorLog.txt
#>

# Function to log and handle errors
function Handle-Error {
    param (
        [string]$ErrorMessage
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
    Add-Content -Path "C:\WindowsUpdateErrorLog.txt" -Value "$timestamp - $ErrorMessage"
}

# Ensure NuGet provider is installed
try {
    Write-Host "Checking NuGet provider..." -ForegroundColor Cyan
    $nuGetProvider = Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue

    if (-not $nuGetProvider) {
        Write-Host "NuGet not found. Installing..." -ForegroundColor Cyan
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
    } else {
        Write-Host "NuGet is already present. Updating..." -ForegroundColor Cyan
        Install-PackageProvider -Name NuGet -Force -ErrorAction Stop
    }
} catch {
    Handle-Error "Failed to install or update NuGet provider: $_"
}

# Install PSWindowsUpdate module
try {
    Write-Host "Ensuring PSWindowsUpdate module is installed..." -ForegroundColor Cyan
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false -ErrorAction Stop
} catch {
    Handle-Error "Failed to install PSWindowsUpdate module: $_"
}

# Import PSWindowsUpdate module
try {
    Write-Host "Importing PSWindowsUpdate module..." -ForegroundColor Cyan
    Import-Module PSWindowsUpdate -ErrorAction Stop
} catch {
    Handle-Error "Failed to import PSWindowsUpdate module: $_"
}

# Scan and filter for Feature Updates
Write-Host "Scanning for Windows Feature Updates..." -ForegroundColor Green
try {
    $updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll | Where-Object { $_.Title -match 'Feature Update' }

    if ($updates -and $updates.Count -gt 0) {
        Write-Host "`nFeature updates found: $($updates.Count)`n" -ForegroundColor Green

        foreach ($update in $updates) {
            try {
                Write-Host "Installing: $($update.Title)" -ForegroundColor Yellow
                Install-WindowsUpdate -KBArticleID $update.KBArticleIDs -AcceptAll -AutoReboot -ErrorAction Stop
            } catch {
                Handle-Error "Failed to install feature update '$($update.Title)': $_"
            }
        }
    } else {
        Write-Host "No feature updates available." -ForegroundColor Yellow
    }
} catch {
    Handle-Error "Failed during update scan or processing: $_"
}

Write-Host "`nWindows update check complete." -ForegroundColor Cyan
