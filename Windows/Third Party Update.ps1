# Ensure script can run (safe, process-only)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

<#
    Purpose: Install WinGet (if missing) and run "winget upgrade --all"
    Scope: Workstations & laptops ONLY â€” Automatically skips servers
    Author: Adrian Bennett
#>

# ---------------------------
# 1. Create logging directory
# ---------------------------
$LogDir = "C:\ProgramData\WinGet-Upgrades"
$Timestamp = Get-Date -Format yyyy-MM-dd_HH-mm
$OutLog = Join-Path $LogDir "upgrade-output-$Timestamp.txt"
$ErrLog = Join-Path $LogDir "upgrade-error-$Timestamp.txt"

if (!(Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory | Out-Null
}

# ---------------------------
# 2. Ensure WinGet is installed
# ---------------------------
Write-Output "Checking for WinGet installation..."

$WinGetPath = "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"

if (!(Test-Path $WinGetPath)) {
    Write-Output "WinGet not found. Installing via Microsoft Store App Installer..."

    # Install App Installer (includes winget)
    $appInstaller = Get-AppxPackage -Name Microsoft.DesktopAppInstaller -AllUsers

    if (!$appInstaller) {
        Write-Output "Installing DesktopAppInstaller..."
        Add-AppxPackage -RegisterByFamilyName -MainPackageFamilyName Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
    } else {
        Write-Output "DesktopAppInstaller already installed."
    }

    Start-Sleep -Seconds 5
}

# Final check
if (!(Test-Path $WinGetPath)) {
    Write-Output "ERROR: WinGet installation failed or not detected."
    exit 1
}

Write-Output "WinGet is installed."

# ---------------------------
# 3. Run WinGet Upgrade All
# ---------------------------
Write-Output "Running winget upgrade --all..."

Start-Process -FilePath $WinGetPath `
    -ArgumentList "upgrade --all --accept-source-agreements --accept-package-agreements" `
    -Wait `
    -WindowStyle Hidden `
    -RedirectStandardOutput $OutLog `
    -RedirectStandardError $ErrLog

Write-Output "WinGet upgrade completed."
Write-Output "Output Log: $OutLog"
Write-Output "Error Log:  $ErrLog"
