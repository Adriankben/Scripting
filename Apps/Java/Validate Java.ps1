$ErrorActionPreference = "Stop"

$targetUpdate = 491

function Get-Java8UpdateNumber {
    param([string]$Version)

    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }

    if ($Version -match '^1\.8\.0_(\d+)$') {
        return [int]$matches[1]
    }

    if ($Version -match '^8\.0\.(\d+)\.\d+$') {
        $raw = $matches[1]
        if ($raw.EndsWith('0') -and $raw.Length -gt 1) {
            return [int]$raw.Substring(0, $raw.Length - 1)
        }
        return [int]$raw
    }

    if ($Version -match '^8u(\d+)$') {
        return [int]$matches[1]
    }

    return $null
}

function Get-Java8Installs {
    Get-ItemProperty -Path @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    ) -ErrorAction SilentlyContinue | Where-Object {
        $_.DisplayName -match 'Java 8|Java\(TM\) 8|JRE 8|JDK 8|Java SE 8'
    } | ForEach-Object {
        $updateNumber = Get-Java8UpdateNumber -Version $_.DisplayVersion

        [PSCustomObject]@{
            Name         = $_.DisplayName
            Version      = $_.DisplayVersion
            UpdateNumber = $updateNumber
        }
    }
}

Write-Output "Pre-check: Checking Java 8 installation..."

$javaInstalls = Get-Java8Installs | Where-Object { $_.UpdateNumber -ne $null }

if (-not $javaInstalls) {
    Write-Output "Java 8 is not installed. Installer should run."
}

$latestJava = $javaInstalls | Sort-Object UpdateNumber -Descending | Select-Object -First 1

Write-Output "Detected Java: $($latestJava.Name)"
Write-Output "Detected version: $($latestJava.Version)"
Write-Output "Detected update: $($latestJava.UpdateNumber)"

if ($latestJava.UpdateNumber -ge $targetUpdate) {
    Write-Output "Java 8 Update $targetUpdate or newer is already installed. Returning failure code to cancel installer."
    exit 1
}

Write-Output "Java 8 is installed but below Update $targetUpdate. Installer should run."
