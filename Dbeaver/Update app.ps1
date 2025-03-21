param (
    [string]$AppName = "Dbeaver"  # Default application, change as needed
)

# Function to check in the registry (both 32-bit & 64-bit)
function Check-Registry {
    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $paths) {
        $found = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -like "*$AppName*" }
        if ($found) { return $true }
    }
    return $false
}

# Function to check using Get-Package
function Check-GetPackage {
    try {
        $found = Get-Package -Name "*$AppName*" -ErrorAction SilentlyContinue
        return ($found -ne $null)
    } catch {
        return $false
    }
}

# Function to check using WMIC (for older systems)
function Check-WMIC {
    $found = wmic product get name | Select-String -Pattern $AppName -ErrorAction SilentlyContinue
    return ($found -ne $null)
}

# Run all checks
$installed = Check-Registry
if (-not $installed) { $installed = Check-GetPackage }
if (-not $installed) { $installed = Check-WMIC }

# Output results
if ($installed) {
    Write-Output "$AppName is installed."
    Exit 1
} else {
    Write-Output "$AppName is NOT installed."
    Exit 0
}
