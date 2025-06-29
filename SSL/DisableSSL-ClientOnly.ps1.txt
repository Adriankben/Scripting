# Ensure script only runs on workstation OS
$osType = (Get-WmiObject -Class Win32_OperatingSystem).ProductType

# ProductType: 1 = Workstation, 2 = Domain Controller, 3 = Server
if ($osType -ne 1) {
    Write-Host "This script is intended for client workstations only. Exiting..." -ForegroundColor Yellow
    exit
}

$sslClientProtocols = @(
    "SSL 2.0\Client",
    "SSL 3.0\Client"
)

foreach ($protocol in $sslClientProtocols) {
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\$protocol"

    # Create the key if it doesn't exist
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    # Set 'Enabled' to 0 and 'DisabledByDefault' to 1
    New-ItemProperty -Path $regPath -Name "Enabled" -Value 0 -PropertyType DWORD -Force | Out-Null
    New-ItemProperty -Path $regPath -Name "DisabledByDefault" -Value 1 -PropertyType DWORD -Force | Out-Null
}

Write-Host "SSL 2.0 and SSL 3.0 (Client-side) have been disabled on this workstation." -ForegroundColor Green
Write-Host "A system reboot is required for the changes to take effect." -ForegroundColor Cyan
