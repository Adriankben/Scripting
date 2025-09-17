# Resolve the path to the App Installer folder
$ResolveWingetPath = Resolve-Path "C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe"

# Check if the resolved path is found
if ($ResolveWingetPath) {
    # Extract the path of the App Installer folder
    $WingetPath = $ResolveWingetPath[-1].Path

    # Check if winget.exe exists in the directory
    $WingetExePath = Join-Path $WingetPath "winget.exe"
    if (Test-Path $WingetExePath) {
        # Change the working directory to the winget folder
        Set-Location $WingetPath

        # Run the winget upgrade command
        .\winget.exe upgrade --all --silent --accept-package-agreements --accept-source-agreements
        Write-Output "winget upgrade completed successfully."
    } else {
        Write-Output "winget.exe not found in $WingetPath"
    }
} else {
    Write-Output "Failed to resolve the path to the App Installer directory."
}



