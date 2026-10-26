<#
.SYNOPSIS
    Reverses Install-WinGet-Server2019.ps1.

.DESCRIPTION
    Reads the rollback state file written by the install script and removes only what it added:
      - App Installer (winget) for all users, and its machine-wide provisioning
      - VCLibs / UI.Xaml dependency packages, only if they were not present before and nothing else uses them
      - The winget PATH entry
      - The VC++ redistributable, only if the install script installed it AND -RemoveVCRedist is passed
        (other software often depends on it, so it is kept by default)

    Without a state file it falls back to removing App Installer and the PATH entry only.

.PARAMETER WorkDir
    Same folder the install script used. Default C:\ProgramData\WinGetInstall.

.PARAMETER RemoveVCRedist
    Also uninstall the VC++ 2015-2022 x64 runtime if the install script added it.

.PARAMETER WhatIf
    Show what would be removed without changing anything.

.EXAMPLE
    powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-WinGet-Server2019.ps1 -WhatIf
    powershell.exe -ExecutionPolicy Bypass -File .\Uninstall-WinGet-Server2019.ps1
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkDir = "$env:ProgramData\WinGetInstall",
    [switch]$RemoveVCRedist
)

$ErrorActionPreference = 'Continue'   # keep going so one failed step doesn't block the rest
$null = New-Item -ItemType Directory -Path $WorkDir -Force
$logFile = Join-Path $WorkDir ("uninstall-{0}.log" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
Start-Transcript -Path $logFile -Append | Out-Null

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Run this script from an elevated (Administrator) PowerShell.' -ForegroundColor Red
    Stop-Transcript | Out-Null; exit 1
}

$stateFile = Join-Path $WorkDir 'rollback-state.json'
$state = $null
if (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    Write-Host "Using rollback state from $($state.Created)"
} else {
    Write-Warn2 "No state file at $stateFile. Removing App Installer and the PATH entry only; dependencies and VC++ are left alone."
}
$errors = 0

# ------------------------------------------------------------------ stop winget processes
Get-Process winget, WindowsPackageManagerServer -ErrorAction SilentlyContinue | ForEach-Object {
    if ($PSCmdlet.ShouldProcess($_.Name, 'Stop process')) { $_ | Stop-Process -Force }
}

# ------------------------------------------------------------------ 0. folder permissions
if ($state -and $state.AclBackupFile -and (Test-Path $state.AclBackupFile) -and (Test-Path $state.AclBackupParent)) {
    Write-Step 'Restoring original WindowsApps folder permissions'
    if ($PSCmdlet.ShouldProcess($state.AclBackupParent, 'icacls /restore')) {
        # The folder belongs to TrustedInstaller again, so take ownership to rewrite the ACL, then give it back
        $first = (Get-Content $state.AclBackupFile -Encoding Unicode -TotalCount 1).Trim()
        $dir = Join-Path $state.AclBackupParent $first
        $null = & takeown.exe /f $dir /r /a /d Y 2>&1
        $out = & icacls.exe $state.AclBackupParent /restore $state.AclBackupFile /c /q 2>&1
        if ($LASTEXITCODE -eq 0) { Write-Ok 'Permissions restored' } else { Write-Warn2 "icacls restore exit code ${LASTEXITCODE}: $out"; $errors++ }
        $null = & icacls.exe $dir /setowner 'NT SERVICE\TrustedInstaller' /t /c /q 2>&1
    }
}

# ------------------------------------------------------------------ 1. App Installer
Write-Step 'Removing App Installer (winget)'
$wasThereBefore = $state -and (@($state.AppxBefore) | Where-Object { $_ -like 'Microsoft.DesktopAppInstaller_*' })
if ($wasThereBefore) {
    Write-Warn2 'App Installer was already installed before the install script ran; leaving it in place.'
} else {
    Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq 'Microsoft.DesktopAppInstaller' | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.PackageName, 'Remove provisioned package')) {
            try { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null; Write-Ok "Deprovisioned $($_.PackageName)" }
            catch { Write-Warn2 "Deprovision failed: $($_.Exception.Message)"; $errors++ }
        }
    }
    Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller | ForEach-Object {
        if ($PSCmdlet.ShouldProcess($_.PackageFullName, 'Remove package for all users')) {
            try { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction Stop; Write-Ok "Removed $($_.PackageFullName)" }
            catch { Write-Warn2 "Remove failed: $($_.Exception.Message)"; $errors++ }
        }
    }
}

# ------------------------------------------------------------------ 2. dependencies
Write-Step 'Removing dependency packages added by the install'
if (-not $state) {
    Write-Host 'Skipped (no state file).'
} else {
    # Runtime first: it depends on VCLibs, so VCLibs can only go once the runtime is gone
    foreach ($name in 'Microsoft.WindowsAppRuntime.*','Microsoft.UI.Xaml.2.8','Microsoft.VCLibs.140.00.UWPDesktop','Microsoft.VCLibs.140.00') {
        Get-AppxPackage -AllUsers -Name $name | Where-Object { $_.Architecture -eq 'X64' -or $_.Architecture -eq 'Neutral' } | Where-Object { $_.PackageFullName -notin @($state.AppxBefore) } | ForEach-Object {
            $full = $_.PackageFullName
            # Leave it if any other installed package still depends on it
            $users = Get-AppxPackage -AllUsers | Where-Object { $_.Dependencies.PackageFullName -contains $full }
            if ($users) {
                Write-Warn2 "Keeping $full; still used by: $(($users.Name | Select-Object -Unique) -join ', ')"
            } elseif ($PSCmdlet.ShouldProcess($full, 'Remove package for all users')) {
                try { Remove-AppxPackage -Package $full -AllUsers -ErrorAction Stop; Write-Ok "Removed $full" }
                catch { Write-Warn2 "Remove failed for ${full}: $($_.Exception.Message)"; $errors++ }
            }
        }
    }
}

# ------------------------------------------------------------------ 3. PATH
Write-Step 'Removing winget from machine PATH'
$machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
$kept = $machinePath -split ';' | Where-Object { $_ -and $_ -notlike '*Microsoft.DesktopAppInstaller_*' }
$newPath = $kept -join ';'
if ($newPath -ne $machinePath.TrimEnd(';')) {
    if ($PSCmdlet.ShouldProcess('Machine PATH', 'Remove DesktopAppInstaller entries')) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine'); Write-Ok 'PATH cleaned'
    }
} else { Write-Host 'No winget entry in PATH.' }

# ------------------------------------------------------------------ 4. VC++ redist
Write-Step 'Visual C++ redistributable'
if (-not ($state -and $state.VCRedistInstalledByUs)) {
    Write-Host 'Not installed by the install script; leaving it.'
} elseif (-not $RemoveVCRedist) {
    Write-Host 'Installed by the install script, but kept (other software often needs it). Pass -RemoveVCRedist to remove.'
} else {
    $vcExe = Join-Path $WorkDir 'downloads\vc_redist.x64.exe'
    if (-not (Test-Path $vcExe)) { Write-Warn2 "Installer not found at $vcExe; remove 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' from Programs and Features."; $errors++ }
    elseif ($PSCmdlet.ShouldProcess('VC++ 2015-2022 x64', 'Uninstall')) {
        $p = Start-Process $vcExe -ArgumentList '/uninstall','/quiet','/norestart' -Wait -PassThru
        if ($p.ExitCode -in 0,3010) { Write-Ok "Uninstalled (exit $($p.ExitCode))" } else { Write-Warn2 "Uninstall exit code $($p.ExitCode)"; $errors++ }
    }
}

# ------------------------------------------------------------------ verify
Write-Step 'Verifying'
$left = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller
if ($left -and -not $wasThereBefore) { Write-Warn2 "Still present: $($left.PackageFullName -join ', ') (a reboot and re-run usually clears this)"; $errors++ }
else { Write-Ok 'App Installer removed (or was pre-existing and kept)' }

if (-not $WhatIfPreference -and $errors -eq 0 -and $state) {
    Rename-Item $stateFile "rollback-state.used-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
}
Write-Host "`nLog: $logFile"
Stop-Transcript | Out-Null
if ($errors) { Write-Host "$errors step(s) had problems; see log." -ForegroundColor Yellow; exit 1 }
Write-Host 'Rollback complete.' -ForegroundColor Green
exit 0
