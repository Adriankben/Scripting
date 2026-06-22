$ErrorActionPreference = "Stop"

# Minimum Cisco Secure Client version you want installed
$targetVersion = [version]"5.1.12.146"

function Get-CiscoSecureClientInstalls {
    Get-ItemProperty -Path @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match 'Cisco Secure Client|Cisco AnyConnect'
    } | ForEach-Object {
        $parsedVersion = $null

        if ($_.DisplayVersion) {
            try {
                $parsedVersion = [version]$_.DisplayVersion
            }
            catch {
                $parsedVersion = $null
            }
        }

        [PSCustomObject]@{
            Name          = $_.DisplayName
            Version       = $_.DisplayVersion
            ParsedVersion = $parsedVersion
            Publisher     = $_.Publisher
            InstallDate   = $_.InstallDate
        }
    }
}

Write-Output "Validation: Checking Cisco Secure Client installation..."

$ciscoInstalls = Get-CiscoSecureClientInstalls | Where-Object {
    $_.ParsedVersion -ne $null
}

if (-not $ciscoInstalls) {
    throw "Cisco Secure Client is not installed. Cancelling installer because this deployment should only upgrade existing installations."
}

$latestCisco = $ciscoInstalls |
    Sort-Object ParsedVersion -Descending |
    Select-Object -First 1

Write-Output "Detected Cisco client: $($latestCisco.Name)"
Write-Output "Detected version: $($latestCisco.Version)"
Write-Output "Required minimum version: $targetVersion"

if ($latestCisco.ParsedVersion -ge $targetVersion) {
    throw "Cisco Secure Client version $($latestCisco.Version) is already at or above target version $targetVersion. Cancelling installer."
}

Write-Output "Cisco Secure Client is installed and below target version. Allowing installer to run."
exit 0