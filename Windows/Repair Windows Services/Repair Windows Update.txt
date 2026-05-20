# Windows Update Connectivity Repair - Workstations
# Safe defaults:
# - Resets update components
# - Repairs system image/files
# - Preserves WSUS/proxy policy unless you explicitly allow policy reset
# - Only resets WinHTTP proxy automatically when WSUS is NOT configured

# Optional switches:
#   $ResetPolicy = $true   # only if you WANT Windows Update policy keys deleted and re-applied by GPO
#   $RunDISM     = $true
#   $RunSFC      = $true

$ResetPolicy = $false
$RunDISM     = $true
$RunSFC      = $true

# Elevate if needed
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    if (-not $PSCommandPath) {
        Write-Host "Please save this script as a .ps1 file and run it as Administrator." -ForegroundColor Yellow
        exit 1
    }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

$ErrorActionPreference = 'Continue'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logDir = Join-Path $env:ProgramData "WURepair"
$null = New-Item -ItemType Directory -Path $logDir -Force -ErrorAction SilentlyContinue
$log = Join-Path $logDir "WURepair-$stamp.log"

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    $line | Tee-Object -FilePath $log -Append
}

function Stop-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -ne 'Stopped') {
            Write-Log "Stopping service: $Name"
            Stop-Service -Name $Name -Force -ErrorAction Continue
            try {
                $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(20))
            } catch {}
        }
        else {
            Write-Log "Service already stopped: $Name"
        }
    }
    catch {
        Write-Log "Could not stop service ${Name}: $($_.Exception.Message)"
    }
}

function Start-ServiceSafe {
    param([string]$Name)
    try {
        $svc = Get-Service -Name $Name -ErrorAction Stop
        if ($svc.Status -ne 'Running') {
            Write-Log "Starting service: $Name"
            Start-Service -Name $Name -ErrorAction Continue
        }
        else {
            Write-Log "Service already running: $Name"
        }
    }
    catch {
        Write-Log "Could not start service ${Name}: $($_.Exception.Message)"
    }
}

function Rename-IfExists {
    param(
        [string]$Path,
        [string]$Suffix = ".bak.$stamp"
    )
    try {
        if (Test-Path $Path) {
            $parent = Split-Path $Path -Parent
            $leaf   = Split-Path $Path -Leaf
            $newLeaf = "$leaf$Suffix"
            $newPath = Join-Path $parent $newLeaf

            if (Test-Path $newPath) {
                Remove-Item -Path $newPath -Recurse -Force -ErrorAction SilentlyContinue
            }

            Rename-Item -Path $Path -NewName $newLeaf -ErrorAction Stop
            Write-Log "Renamed: $Path -> $newPath"
        }
        else {
            Write-Log "Not found, skipped: $Path"
        }
    }
    catch {
        Write-Log "Rename failed for ${Path}: $($_.Exception.Message)"
    }
}

Write-Log "=== Windows Update repair started ==="

# Collect state
$wuPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$auPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
$usingWSUS = $false
$wsusServer = $null

try {
    if (Test-Path $wuPolicyPath) {
        $wuPolicy = Get-ItemProperty -Path $wuPolicyPath -ErrorAction SilentlyContinue
        if ($null -ne $wuPolicy.WUServer -and $wuPolicy.WUServer -ne '') {
            $usingWSUS = $true
            $wsusServer = $wuPolicy.WUServer
        }
    }
}
catch {}

Write-Log ("WSUS configured: {0}" -f $usingWSUS)
if ($wsusServer) {
    Write-Log "WSUS server: $wsusServer"
}

try {
    $winHttpProxy = (netsh winhttp show proxy) 2>&1 | Out-String
    Write-Log "Current WinHTTP proxy:`n$winHttpProxy"
}
catch {
    Write-Log "Could not read WinHTTP proxy: $($_.Exception.Message)"
}

# Basic connectivity checks
$targets = @()
if ($usingWSUS -and $wsusServer) {
    try {
        $uri = [uri]$wsusServer
        $targets += $uri.Host
    }
    catch {
        Write-Log "WSUS URL parsing failed: $wsusServer"
    }
}
else {
    $targets += 'windowsupdate.microsoft.com', 'download.windowsupdate.com', 'update.microsoft.com'
}

foreach ($t in $targets | Select-Object -Unique) {
    try {
        $ok = Test-NetConnection -ComputerName $t -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
        Write-Log "Connectivity to ${t}:443 = $ok"
    }
    catch {
        Write-Log "Connectivity test failed for ${t}: $($_.Exception.Message)"
    }
}

# Stop services
'bits','wuauserv','cryptsvc','msiserver','dosvc','usosvc' | ForEach-Object { Stop-ServiceSafe $_ }

# Clear downloader queue
try {
    Get-ChildItem "$env:ALLUSERSPROFILE\Microsoft\Network\Downloader\qmgr*.dat" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem "$env:ALLUSERSPROFILE\Application Data\Microsoft\Network\Downloader\qmgr*.dat" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Log "Cleared BITS qmgr*.dat files"
}
catch {
    Write-Log "Failed clearing qmgr files: $($_.Exception.Message)"
}

# Reset network pieces
try {
    ipconfig /flushdns | Out-Null
    Write-Log "Flushed DNS cache"
}
catch {
    Write-Log "ipconfig /flushdns failed: $($_.Exception.Message)"
}

try {
    netsh winsock reset | Tee-Object -FilePath $log -Append | Out-Null
    Write-Log "Winsock reset completed"
}
catch {
    Write-Log "Winsock reset failed: $($_.Exception.Message)"
}

# Reset WinHTTP safely:
# only do it automatically when WSUS is NOT configured
if (-not $usingWSUS) {
    try {
        netsh winhttp reset proxy | Tee-Object -FilePath $log -Append | Out-Null
        netsh winhttp reset autoproxy | Tee-Object -FilePath $log -Append | Out-Null
        Write-Log "Reset WinHTTP proxy/autoproxy"
    }
    catch {
        Write-Log "WinHTTP proxy reset failed: $($_.Exception.Message)"
    }
}
else {
    Write-Log "Skipped WinHTTP proxy reset because WSUS is configured"
}

# Reset update stores
Rename-IfExists -Path "$env:SystemRoot\SoftwareDistribution"
Rename-IfExists -Path "$env:SystemRoot\System32\catroot2"

# Optional: remove Windows Update policy keys so GPO can reapply them
if ($ResetPolicy) {
    foreach ($path in @(
        'HKCU:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate',
        'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate'
    )) {
        try {
            if (Test-Path $path) {
                Remove-Item -Path $path -Recurse -Force -ErrorAction Stop
                Write-Log "Deleted policy key: $path"
            }
            else {
                Write-Log "Policy key not present: $path"
            }
        }
        catch {
            Write-Log "Failed deleting policy key ${path}: $($_.Exception.Message)"
        }
    }

    try {
        gpupdate /force | Tee-Object -FilePath $log -Append | Out-Null
        Write-Log "gpupdate /force completed"
    }
    catch {
        Write-Log "gpupdate failed: $($_.Exception.Message)"
    }
}

# Set sensible startup types
try { Set-Service bits -StartupType Automatic } catch {}
try { Set-Service wuauserv -StartupType Manual } catch {}
try { Set-Service cryptsvc -StartupType Automatic } catch {}
try { Set-Service msiserver -StartupType Manual } catch {}
try { Set-Service usosvc -StartupType Manual } catch {}
try { Set-Service dosvc -StartupType Automatic } catch {}

# Start services back up
'cryptsvc','bits','wuauserv','msiserver','dosvc','usosvc' | ForEach-Object { Start-ServiceSafe $_ }

# DISM then SFC
if ($RunDISM) {
    try {
        Write-Log "Running DISM /Online /Cleanup-Image /RestoreHealth"
        DISM.exe /Online /Cleanup-Image /RestoreHealth | Tee-Object -FilePath $log -Append | Out-Null
        Write-Log "DISM completed"
    }
    catch {
        Write-Log "DISM failed: $($_.Exception.Message)"
    }
}

if ($RunSFC) {
    try {
        Write-Log "Running sfc /scannow"
        sfc /scannow | Tee-Object -FilePath $log -Append | Out-Null
        Write-Log "SFC completed"
    }
    catch {
        Write-Log "SFC failed: $($_.Exception.Message)"
    }
}

# Generate readable Windows Update log
try {
    $wuReadableLog = Join-Path $logDir "WindowsUpdate-$stamp.log"
    Get-WindowsUpdateLog -LogPath $wuReadableLog -ErrorAction SilentlyContinue | Out-Null
    Write-Log "Generated readable Windows Update log: $wuReadableLog"
}
catch {
    Write-Log "Get-WindowsUpdateLog failed: $($_.Exception.Message)"
}

# Try to trigger a scan
try {
    $uso = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
    if (Test-Path $uso) {
        Start-Process -FilePath $uso -ArgumentList "StartScan" -WindowStyle Hidden -ErrorAction SilentlyContinue
        Write-Log "Triggered UsoClient StartScan"
    }
    else {
        Write-Log "UsoClient.exe not found"
    }
}
catch {
    Write-Log "Could not trigger UsoClient StartScan: $($_.Exception.Message)"
}

Write-Log "=== Repair complete ==="
Write-Host ""
Write-Host "Done. Recommended next steps:" -ForegroundColor Green
Write-Host "1. Reboot the workstation"
Write-Host "2. Open Settings > Windows Update > Check for updates"
Write-Host "3. Review log: $log"
Write-Host ""
if ($usingWSUS) {
    Write-Host "WSUS is configured on this device: $wsusServer" -ForegroundColor Yellow
    Write-Host "If updates still fail, verify the workstation can reach that WSUS server and that any required proxy does not require user authentication." -ForegroundColor Yellow
}
else {
    Write-Host "If updates still fail, verify outbound access to Microsoft update endpoints over HTTP/HTTPS." -ForegroundColor Yellow
}