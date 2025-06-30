# PowerShell script to update missing Windows updates with error handling

# Install NuGet provider if missing (required for PowerShellGet)
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
    Write-Host "Installing NuGet provider..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

# Install PSWindowsUpdate module if it's not already installed
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "Installing PSWindowsUpdate module..." -ForegroundColor Cyan
    Install-Module -Name PSWindowsUpdate -Force -SkipPublisherCheck
}

# Import the PSWindowsUpdate module
Import-Module PSWindowsUpdate

# Define a function to handle errors gracefully
function Handle-Error {
    param (
        [string]$ErrorMessage
    )
    
    Write-Host "Error: $ErrorMessage" -ForegroundColor Red
    # Log the error to a file for further analysis
    Add-Content -Path "C:\WindowsUpdateErrorLog.txt" -Value "$(Get-Date) - $ErrorMessage"
}

# Function to check for missing updates
function Check-For-Updates {
    try {
        Write-Host "Checking for missing updates..." -ForegroundColor Cyan
        # Get pending updates using Get-WindowsUpdate without parameters
        $missingUpdates = Get-WindowsUpdate
        if ($missingUpdates.Count -eq 0) {
            Write-Host "No missing updates found." -ForegroundColor Green
        } else {
            Write-Host "$($missingUpdates.Count) updates are pending." -ForegroundColor Yellow
            return $missingUpdates
        }
    } catch {
        Handle-Error "Failed to check for updates: $_"
    }
}

# Function to install the updates
function Install-Updates {
    param (
        [Parameter(Mandatory = $true)]
        [array]$UpdatesToInstall
    )
    
    try {
        Write-Host "Starting the installation of updates..." -ForegroundColor Cyan
        $UpdatesToInstall | ForEach-Object {
            Write-Host "Installing update: $($_.KBArticleIDs)" -ForegroundColor Yellow
            Install-WindowsUpdate -KBArticleID $_.KBArticleIDs -AcceptAll -AutoReboot
        }
        Write-Host "Updates installation completed successfully." -ForegroundColor Green
    } catch {
        Handle-Error "Failed to install updates: $_"
    }
}

# Main script execution
try {
    $missingUpdates = Check-For-Updates
    if ($missingUpdates) {
        Install-Updates -UpdatesToInstall $missingUpdates
    }
} catch {
    Handle-Error "Unexpected error during script execution: $_"
}
