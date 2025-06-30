# List installed software from 32-bit and 64-bit registry locations
$softwareKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$installedSoftware = @()

foreach ($key in $softwareKeys) {
    if (Test-Path $key) {
        $installedSoftware += Get-ItemProperty $key\* | Select-Object DisplayName, DisplayVersion, Publisher, InstallDate
    }
}

# Output the list of installed software
$installedSoftware | Format-Table -AutoSize
