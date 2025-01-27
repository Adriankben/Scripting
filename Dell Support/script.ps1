$dcuInstallerUrl = "https://downloads.dell.com/serviceability/catalog/SupportAssistInstaller.exe"  # Replace with the latest version URL
$dcuInstallerPath = "$env:TEMP\DellCommandUpdate.exe"

# Check if Dell Command Update (DCU) is installed
function Check-DCU {
    $dcuPath = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    if (Test-Path $dcuPath) {
        Write-Host "Dell Command Update is installed."
        return $true
    } else {
        Write-Host "Dell Command Update is not installed."
        return $false
    }
}

# Download and install DCU if not installed
function Install-DCU {
    Write-Host "Downloading Dell Command Update..."
    Invoke-WebRequest -Uri $dcuInstallerUrl -OutFile $dcuInstallerPath -ErrorAction Stop
    Write-Host "Installing Dell Command Update..."
    Start-Process -FilePath $dcuInstallerPath -ArgumentList "/silent" -Wait
}

# Update BIOS using DCU
function Update-BIOS {
    $dcuCliPath = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
    Write-Host "Checking for BIOS updates..."
    Start-Process -FilePath $dcuCliPath -/ "/applyUpdates -reboot=disable" -Wait
    Write-Host "BIOS update process started. System may reboot."
}

# Main script execution
if (-not (Check-DCU)) {
    Install-DCU
}

if (Check-DCU) {
    Update-BIOS
} else {
    Write-Host "Failed to install Dell Command Update. Exiting..."
    exit 1
}
