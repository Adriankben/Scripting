# --- Self-Healing Third-Party App Updater ---
# Checks for WinGet, installs the LATEST version dynamically if missing, and updates apps.

$ErrorActionPreference = "Stop"

function Install-LatestWinGet {
    Write-Host "WinGet missing or broken. Fetching latest release info..." -ForegroundColor Yellow
    
    # 1. Force TLS 1.2/1.3 for security/compatibility
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

    try {
        # 2. Query GitHub API for the official latest release
        $latestRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
        
        # 3. Find the asset ending in '.msixbundle'
        $installerAsset = $latestRelease.assets | Where-Object { $_.name -like "*.msixbundle" } | Select-Object -First 1
        
        if (-not $installerAsset) { throw "Could not find .msixbundle in latest release." }

        # 4. Download
        $tempPath = "$env:TEMP\winget_latest.msixbundle"
        Write-Host "Downloading $($installerAsset.name)..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri $installerAsset.browser_download_url -OutFile $tempPath

        # 5. Install
        Write-Host "Installing App Installer..." -ForegroundColor Cyan
        Add-AppxPackage -Path $tempPath
        Write-Host "WinGet successfully installed!" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install WinGet: $_"
        Exit
    }
}

# --- MAIN EXECUTION ---

Write-Host "--- Checking System Status ---" -ForegroundColor Cyan

# Check if winget command exists
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    Install-LatestWinGet
} else {
    Write-Host "WinGet is already installed." -ForegroundColor Green
}

# Run the update
Write-Host "`n--- Starting App Updates ---" -ForegroundColor Cyan
# --include-unknown: Updates apps even if the version number isn't perfectly recognized
# --accept-source-agreements: Auto-accepts store agreements
winget upgrade --all --silent --accept-package-agreements --accept-source-agreements --include-unknown

Write-Host "`nAll operations complete." -ForegroundColor Green
