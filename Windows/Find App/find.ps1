# Function to get installed apps from a given registry path
function Get-InstalledApps {
    param (
        [string]$keyPath,
        [string]$searchTerm
    )
    $installedApps = @()  # Array to store installed application names

    # Loop through each registry key and retrieve the DisplayName property (the application name)
    foreach ($key in Get-ChildItem -Path $keyPath -Recurse -ErrorAction SilentlyContinue) {
        # Check if the DisplayName property exists and contains the search term
        $app = Get-ItemProperty -Path $key.PSPath -ErrorAction SilentlyContinue
        if ($app.DisplayName -like "*$searchTerm*") {
            $installedApps += $app.DisplayName
        }
    }

    return $installedApps
}

# Initialize the list to store installed applications
$installedAppsList = @()

# Search for applications containing "X"
$searchTerm = "Zscaler"

# Check for 64-bit registry hive (for 64-bit systems) - HKLM\Software
$installedAppsList += Get-InstalledApps "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" $searchTerm

# Check for 32-bit registry hive (for both 32-bit and 64-bit systems) - HKLM\Software\WOW6432Node
$installedAppsList += Get-InstalledApps "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall" $searchTerm

# Check for installed apps in 64-bit registry location
if ([System.Environment]::Is64BitOperatingSystem) {
    $installedAppsList += Get-InstalledApps "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall" $searchTerm
}

# Display the list of installed applications
if ($installedAppsList.Count -gt 0) {
    Write-Host "Installed Applications containing '$searchTerm':"
    $installedAppsList | Sort-Object | ForEach-Object { Write-Host $_ }
    Exit 0
} else {
    Write-Host "No installed applications found containing '$searchTerm'."
    Exit 1
}
