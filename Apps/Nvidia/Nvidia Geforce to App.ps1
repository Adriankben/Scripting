# Requires: Run as Administrator
# Purpose:
# - Detect NVIDIA GPU
# - If GeForce Experience is installed, uninstall it
# - Download and install latest NVIDIA App from NVIDIA's official page
# - Optionally install latest NVIDIA driver silently if a direct driver EXE URL is supplied

$ErrorActionPreference = 'Stop'

# OPTIONAL:
# Leave blank to skip driver install.
# If you want full unattended driver install, paste the exact NVIDIA driver .exe URL here.
$DriverExeUrl = ""

# Working folder
$WorkRoot = Join-Path $env:ProgramData "NVIDIA-App-Upgrade"
New-Item -ItemType Directory -Path $WorkRoot -Force | Out-Null

function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] $Message"
}

function Test-NvidiaGpuPresent {
    $gpu = Get-CimInstance Win32_VideoController |
        Where-Object {
            $_.Name -match 'NVIDIA|GeForce|RTX|GTX|Quadro'
        } |
        Select-Object -First 1

    return $gpu
}

function Get-UninstallEntries {
    $paths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
    }
}

function Uninstall-GeForceExperience {
    $apps = Get-UninstallEntries | Where-Object {
        $_.DisplayName -match 'GeForce Experience'
    }

    if (-not $apps) {
        Write-Log "GeForce Experience not found."
        return
    }

    foreach ($app in $apps) {
        Write-Log "Found GeForce Experience: $($app.DisplayName)"

        $uninstall = $app.UninstallString
        if ([string]::IsNullOrWhiteSpace($uninstall)) {
            Write-Log "No uninstall string found for $($app.DisplayName)."
            continue
        }

        Write-Log "Attempting silent uninstall..."

        # MSI uninstall
        if ($uninstall -match 'MsiExec\.exe') {
            $args = $uninstall -replace '(?i).*MsiExec\.exe', ''
            $args = $args.Trim()

            if ($args -notmatch '/x') {
                $args = $args -replace '(?i)/I', '/X'
            }

            if ($args -notmatch '(?i)/qn') {
                $args += ' /qn /norestart'
            }

            Start-Process -FilePath "msiexec.exe" -ArgumentList $args -Wait -NoNewWindow
        }
        else {
            # EXE uninstall
            $exe = $null
            $args = $null

            if ($uninstall.StartsWith('"')) {
                $parts = $uninstall -split '"'
                $exe = $parts[1]
                $args = ($parts[2..($parts.Length - 1)] -join '"').Trim()
            }
            else {
                $split = $uninstall.Split(' ', 2)
                $exe = $split[0]
                $args = if ($split.Count -gt 1) { $split[1] } else { '' }
            }

            # Common silent flags if none exist
            if ($args -notmatch '(?i)/quiet|/qn|/s|/silent') {
                $args = "$args /S"
            }

            Start-Process -FilePath $exe -ArgumentList $args -Wait -NoNewWindow
        }

        Write-Log "Uninstall attempt completed for GeForce Experience."
    }
}

function Get-NvidiaAppDownloadUrl {
    $pageUrl = "https://www.nvidia.com/en-us/software/nvidia-app/"
    Write-Log "Getting NVIDIA App download link from official NVIDIA page..."
    $resp = Invoke-WebRequest -Uri $pageUrl -UseBasicParsing

    $patterns = @(
        'https://[A-Za-z0-9\.-]+/nvapp/client/[0-9\.]+/NVIDIA_app_v[0-9\.]+\.exe',
        'https://[A-Za-z0-9\.-]+/nvapp/client/[0-9\.]+/NVIDIA_app_beta_v[0-9\.]+\.exe'
    )

    foreach ($pattern in $patterns) {
        $match = [regex]::Match($resp.Content, $pattern)
        if ($match.Success) {
            return $match.Value
        }
    }

    throw "Could not determine NVIDIA App download URL from official page."
}

function Install-NvidiaApp {
    $appUrl = Get-NvidiaAppDownloadUrl
    $appExe = Join-Path $WorkRoot "NVIDIA_App.exe"

    Write-Log "Downloading NVIDIA App..."
    Invoke-WebRequest -Uri $appUrl -OutFile $appExe -UseBasicParsing

    Write-Log "Installing NVIDIA App silently..."
    Start-Process -FilePath $appExe -ArgumentList "/s" -Wait -NoNewWindow

    Write-Log "NVIDIA App install complete."
}

function Install-NvidiaDriverFromUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url
    )

    $driverExe = Join-Path $WorkRoot "NVIDIA_Driver.exe"
    $extractDir = Join-Path $WorkRoot "DriverExtract"

    if (Test-Path $extractDir) {
        Remove-Item $extractDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

    Write-Log "Downloading NVIDIA driver package..."
    Invoke-WebRequest -Uri $Url -OutFile $driverExe -UseBasicParsing

    Write-Log "Extracting driver package..."
    # NVIDIA driver packages usually support extraction via -s -extractonly or by launching once.
    # This sequence handles most current packages.
    Start-Process -FilePath $driverExe -ArgumentList "-s -extractonly `"$extractDir`"" -Wait -NoNewWindow -ErrorAction SilentlyContinue

    if (-not (Test-Path (Join-Path $extractDir "setup.exe"))) {
        Write-Log "Primary extraction method did not expose setup.exe. Trying alternate extraction..."
        Start-Process -FilePath $driverExe -ArgumentList "-s" -Wait -NoNewWindow -ErrorAction SilentlyContinue

        # Fallback: search common NVIDIA extraction locations
        $setup = Get-ChildItem "C:\NVIDIA" -Filter setup.exe -Recurse -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1

        if ($setup) {
            $setupPath = $setup.FullName
        }
        else {
            throw "Could not locate extracted NVIDIA driver setup.exe."
        }
    }
    else {
        $setupPath = Join-Path $extractDir "setup.exe"
    }

    Write-Log "Installing NVIDIA display driver silently..."
    Start-Process -FilePath $setupPath -ArgumentList "-s -n Display.Driver" -Wait -NoNewWindow

    Write-Log "Driver installation complete."
}

# MAIN
Write-Log "Checking for NVIDIA GPU..."
$gpu = Test-NvidiaGpuPresent

if (-not $gpu) {
    Write-Log "No NVIDIA GPU detected. Exiting."
    exit 0
}

Write-Log "Detected NVIDIA GPU: $($gpu.Name)"

Uninstall-GeForceExperience
Install-NvidiaApp

if (-not [string]::IsNullOrWhiteSpace($DriverExeUrl)) {
    Install-NvidiaDriverFromUrl -Url $DriverExeUrl
}
else {
    Write-Log "Driver URL not supplied. NVIDIA App installed/updated, but driver package install was skipped."
    Write-Log "For fully silent latest driver deployment, supply the direct NVIDIA driver .exe URL."
}

Write-Log "Completed."
exit 0