<#
.SYNOPSIS
Checks and optionally increases the Windows ServicesPipeTimeout registry value.

.DESCRIPTION
This script reviews the current ServicesPipeTimeout value under:
HKLM:\SYSTEM\CurrentControlSet\Control

If the value does not exist, the script creates it.
If the value exists but is lower than the desired value, the script increases it.
If the value is already equal to or greater than the desired value, no change is made.

A backup text file is written to C:\Temp before any change is applied.

.NOTES
- Run in an elevated PowerShell session.
- A reboot is required for changes to take effect.
- Intended for troubleshooting slow-starting Windows services that hit startup timeout errors.
#>

# Desired timeout in milliseconds.
# 120000 = 120 seconds
$DesiredTimeout = 120000

# Registry settings
$RegPath   = 'HKLM:\SYSTEM\CurrentControlSet\Control'
$ValueName = 'ServicesPipeTimeout'

# Backup location
$BackupFolder = 'C:\Temp'
$BackupFile   = Join-Path $BackupFolder "ServicesPipeTimeout-backup-$(Get-Date -Format yyyyMMdd-HHmmss).txt"

# Ensure backup folder exists
if (-not (Test-Path $BackupFolder)) {
    New-Item -Path $BackupFolder -ItemType Directory -Force | Out-Null
}

Write-Host "Checking current ServicesPipeTimeout value..." -ForegroundColor Cyan

# Default to null if the registry value is not present
$currentValue = $null

try {
    $currentValue = (Get-ItemProperty -Path $RegPath -Name $ValueName -ErrorAction Stop).$ValueName
    Write-Host "Current value detected: $currentValue ms" -ForegroundColor Yellow
}
catch {
    Write-Host "ServicesPipeTimeout is not currently set. Windows is using the default timeout." -ForegroundColor Yellow
}

# Save current state to a backup file for reference
@"
Timestamp      : $(Get-Date)
Computer       : $env:COMPUTERNAME
User           : $env:USERNAME
Registry Path  : $RegPath
Value Name     : $ValueName
Current Value  : $currentValue
Desired Value  : $DesiredTimeout
"@ | Out-File -FilePath $BackupFile -Encoding utf8 -Force

Write-Host "Backup written to: $BackupFile" -ForegroundColor Green

# Create or update the registry value only when needed
if ($null -eq $currentValue) {
    New-ItemProperty -Path $RegPath -Name $ValueName -PropertyType DWord -Value $DesiredTimeout -Force | Out-Null
    Write-Host "Created $ValueName with value $DesiredTimeout ms." -ForegroundColor Green
}
elseif ([int]$currentValue -lt $DesiredTimeout) {
    Set-ItemProperty -Path $RegPath -Name $ValueName -Value $DesiredTimeout -Force
    Write-Host "Increased $ValueName from $currentValue ms to $DesiredTimeout ms." -ForegroundColor Green
}
else {
    Write-Host "No change made. Current value ($currentValue ms) is already greater than or equal to the desired value ($DesiredTimeout ms)." -ForegroundColor Green
}

Write-Host ""
Write-Host "A reboot is required for the change to take effect." -ForegroundColor Magenta