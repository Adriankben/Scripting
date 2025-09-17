$uninstallPath = "C:\Program Files\Dell\Dell Peripheral Manager\Uninstall.exe"

if (Test-Path $uninstallPath) {
    Write-Output "Found unins000.exe at $uninstallPath. Running it now..."
    
    Start-Process -FilePath $uninstallPath -ArgumentList "/silent" -NoNewWindow -Wait
    
    Write-Output "Uninstall command sent to uninstaller.exe."
} else {
    Write-Output "Dell Peripheral Manager uninstaller not found at the specified path."
}