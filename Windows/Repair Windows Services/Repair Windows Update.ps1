<#
.SYNOPSIS
    Repairs Windows Update components and connectivity on workstations.

.HOW TO RUN
    Copy and paste: open Windows PowerShell (64-bit) as Administrator, paste
    this entire file, and press Enter. Your session stays open and its
    settings are not changed. Check the result afterwards with $LASTEXITCODE.

    As a file: save as a .ps1 and run it elevated, or deploy it through
    Intune / RMM. It relaunches itself elevated and in 64-bit if needed.

    Change behavior by editing the SETTINGS section below before pasting.

.DESCRIPTION
    Default actions:
      - Detects WSUS (WUServer + UseWUServer=1) and the WinHTTP proxy (read from
        the registry, so the check is not locale dependent)
      - Tests TCP reachability of the WSUS server on its real port, or of the
        Microsoft update endpoints, and of the WinHTTP proxy if one is set
      - Stops BITS, Windows Update, Cryptographic Services, Delivery
        Optimization and Update Orchestrator, and verifies they actually stopped
      - Clears the BITS queue (qmgr*.dat)
      - Renames SoftwareDistribution and catroot2 (only after services are
        confirmed stopped) and prunes old backups created by this script
      - Restarts the services
      - Runs DISM /RestoreHealth and SFC, checking real exit codes
      - Generates a readable WindowsUpdate.log and triggers a scan

    Opt-in actions (SETTINGS):
      ResetWinHttpProxy   netsh winhttp reset proxy / autoproxy
      ResetWinsock        netsh winsock reset (requires reboot)
      ResetPolicy         Backs up and deletes HKLM Windows Update policy keys,
                          then runs gpupdate. Domain-joined devices only.

    Logs are written to %ProgramData%\WURepair, which is locked down to
    SYSTEM and Administrators before anything is written.

.NOTES
    Result codes ($LASTEXITCODE when pasted, process exit code when run as a file):
      0  All steps succeeded
      1  One or more repair steps failed (see log)
      2  Precondition failure (settings, elevation, 32-bit host, insecure log path)

    A reboot is recommended after every run.

    References:
      https://learn.microsoft.com/windows/deployment/update/windows-update-resources
      https://learn.microsoft.com/windows-server/administration/windows-commands/netsh-winhttp
      https://support.microsoft.com/help/900935
#>
& {
# ============================== SETTINGS ==============================
# $true to reset the machine WinHTTP proxy to direct access. The current value
# is logged first. Do not use on devices that need a proxy to reach updates.
$ResetWinHttpProxy = $false
# $true to reset the Winsock catalog. Requires a reboot and can disrupt VPN
# clients and network filtering agents.
$ResetWinsock = $false
# $true to back up and delete HKLM Windows Update policy keys, then gpupdate.
# Refused on devices that are not domain joined.
$ResetPolicy = $false
# DISM repair source for WSUS clients that cannot reach Windows Update.
# Leave empty to use Windows Update. Examples:
#   'WIM:D:\sources\install.wim:6'   'ESD:D:\sources\install.esd:6'
#   'D:\sources\sxs'                 '\\server\share\sxs'
$RepairSource = ''
$SkipDISM = $false
$SkipSFC  = $false
$SkipScan = $false            # skip WindowsUpdate.log generation and scan trigger
$KeepBackups           = 2    # SoftwareDistribution/catroot2 backups to keep (1-10)
$ServiceTimeoutSeconds = 30   # wait per service stop/start (5-300)
# ============================ END SETTINGS ============================
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# State lives in this block only, so nothing leaks into a pasted session.
$state = @{
    ExitCode       = 0
    RebootRequired = $false
    LogFile        = $null
    LogDir         = $null
    Suffix         = ''
    ServicesTouched = $false
}
$Failures  = New-Object System.Collections.Generic.List[string]
$Warnings  = New-Object System.Collections.Generic.List[string]
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$RunFromFile = -not [string]::IsNullOrEmpty($PSCommandPath)
$AbortToken  = 'WURepair-Abort-' + [Guid]::NewGuid().ToString('N')
function Stop-Repair {
    param([Parameter(Mandatory)][int]$Code, [Parameter(Mandatory)][string]$Message)
    $state.ExitCode = $Code
    if ($state.LogFile) { Write-Log $Message -Level ERROR } else { Write-Host $Message -ForegroundColor Red }
    throw $AbortToken
}
function Write-Log {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level = 'INFO',
        [switch]$FileOnly
    )
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($state.LogFile) {
        try { [IO.File]::AppendAllText($state.LogFile, $line + [Environment]::NewLine, $Utf8NoBom) }
        catch { Write-Host "Log write failed: $($_.Exception.Message)" -ForegroundColor Red }
    }
    if (-not $FileOnly) {
        switch ($Level) {
            'WARN'  { Write-Host $line -ForegroundColor Yellow }
            'ERROR' { Write-Host $line -ForegroundColor Red }
            default { Write-Host $line }
        }
    }
}
function Add-Failure { param([Parameter(Mandatory)][string]$Message) $Failures.Add($Message); Write-Log $Message -Level ERROR }
function Add-Warning { param([Parameter(Mandatory)][string]$Message) $Warnings.Add($Message); Write-Log $Message -Level WARN }
function Test-IsReparsePoint {
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Initialize-LogDirectory {
    # Standard users can create folders under ProgramData. A pre-planted folder
    # or junction would let an elevated process write wherever it points, so
    # verify ownership, refuse reparse points, and lock the ACL before use.
    $base = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($base)) { throw 'Could not resolve the ProgramData folder.' }
    $dir = Join-Path $base 'WURepair'
    $sidSystem = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
    $sidAdmins = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
    $sidSelf   = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $trusted   = @($sidSystem.Value, $sidAdmins.Value, $sidSelf.Value)
    if (Test-Path -LiteralPath $dir) {
        $item = Get-Item -LiteralPath $dir -Force
        if (-not $item.PSIsContainer) { throw "$dir exists and is not a directory." }
        if (Test-IsReparsePoint $item) { throw "$dir is a reparse point (junction or symlink). Investigate before running." }
        $owner = (Get-Acl -LiteralPath $dir).GetOwner([Security.Principal.SecurityIdentifier])
        if ($trusted -notcontains $owner.Value) { throw "$dir is owned by $owner, not SYSTEM or Administrators. Investigate before running." }
    }
    else {
        $null = New-Item -ItemType Directory -Path $dir
        $item = Get-Item -LiteralPath $dir -Force
        if (Test-IsReparsePoint $item) { throw "$dir became a reparse point during creation." }
    }
    $inherit = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $prop    = [Security.AccessControl.PropagationFlags]::None
    $full    = [Security.AccessControl.FileSystemRights]::FullControl
    $allow   = [Security.AccessControl.AccessControlType]::Allow
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidSystem, $full, $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sidAdmins, $full, $inherit, $prop, $allow)))
    try {
        $withOwner = New-Object Security.AccessControl.DirectorySecurity
        $withOwner.SetSecurityDescriptorSddlForm($acl.GetSecurityDescriptorSddlForm('Access'))
        $withOwner.SetOwner($sidAdmins)
        Set-Acl -LiteralPath $dir -AclObject $withOwner
    }
    catch {
        Set-Acl -LiteralPath $dir -AclObject $acl
    }
    $planted = @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue | Where-Object { Test-IsReparsePoint $_ })
    if ($planted.Count -gt 0) {
        $Warnings.Add("Reparse points found in ${dir}: $($planted.Name -join ', '). They were not used; review them.")
    }
    return $dir
}
function New-ExclusiveFile {
    # CreateNew fails if anything (including a planted link) already exists.
    param([Parameter(Mandatory)][string]$Path)
    $fs = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $fs.Dispose()
}
function Get-RegistryValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Item -LiteralPath $Path).GetValue($Name, $null)
}
function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @(),
        [switch]$UnicodeOutput
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Executable not found: $FilePath"
    }
    # Windows PowerShell 5.1 turns redirected stderr into terminating errors
    # when ErrorActionPreference is Stop, so relax it for the native call.
    $ErrorActionPreference = 'Continue'
    $previousEncoding = $null
    if ($UnicodeOutput) {
        try {
            $previousEncoding = [Console]::OutputEncoding
            [Console]::OutputEncoding = [Text.Encoding]::Unicode
        }
        catch { $previousEncoding = $null }
    }
    try {
        $output = & $FilePath @ArgumentList 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        if ($null -ne $previousEncoding) {
            try { [Console]::OutputEncoding = $previousEncoding } catch { }
        }
    }
    foreach ($entry in @($output)) {
        $text = ([string]$entry) -replace "`0", ''
        $text = ($text -split "`r")[-1].TrimEnd()
        if ([string]::IsNullOrWhiteSpace($text)) { continue }
        if ($text -match '^\s*\[[=\s]*[\d.]*%?[=\s]*\]\s*$') { continue }   # DISM progress bar
        Write-Log "    $text" -FileOnly
    }
    if ($null -eq $exitCode) { $exitCode = 0 }
    return [int]$exitCode
}
function Format-ExitCode {
    param([Parameter(Mandatory)][int]$Code)
    return ('{0} (0x{1:X8})' -f $Code, $Code)
}
function Test-TcpPort {
    param(
        [Parameter(Mandatory)][string]$HostName,
        [Parameter(Mandatory)][ValidateRange(1, 65535)][int]$Port,
        [int]$TimeoutMs = 5000
    )
    if ($HostName -notmatch '^[A-Za-z0-9.\-:\[\]]{1,253}$') { return $false }
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync($HostName, $Port)
        return ($task.Wait($TimeoutMs) -and $client.Connected)
    }
    catch { return $false }
    finally { $client.Dispose() }
}
function Get-WinHttpProxy {
    # Reads WinHttpSettings directly so the result does not depend on the
    # display language of netsh output.
    # Layout: DWORD version, DWORD counter, DWORD flags, DWORD proxy length,
    # proxy string (ASCII), DWORD bypass length, bypass string.
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Connections'
    $result = [pscustomobject]@{ Known = $true; Configured = $false; Server = ''; HostName = ''; Port = 0; RawHex = '' }
    $bytes = Get-RegistryValue -Path $key -Name 'WinHttpSettings'
    if ($null -eq $bytes) { return $result }   # Not set means direct access
    if ($bytes -isnot [byte[]] -or $bytes.Length -lt 16) { $result.Known = $false; return $result }
    $result.RawHex = [BitConverter]::ToString($bytes)
    $flags = [BitConverter]::ToInt32($bytes, 8)
    $len   = [BitConverter]::ToInt32($bytes, 12)
    if ($len -lt 0 -or (16 + $len) -gt $bytes.Length) { $result.Known = $false; return $result }
    if (($flags -band 2) -eq 0 -or $len -eq 0) { return $result }
    $server = [Text.Encoding]::ASCII.GetString($bytes, 16, $len).Trim()
    $result.Configured = $true
    $result.Server = $server
    # Formats: host:port | http=host:port;https=host:port | http://host:port
    $first = ($server -split ';')[0]
    $first = $first -replace '^(?i)[a-z]+=', '' -replace '^(?i)https?://', ''
    $first = $first.TrimEnd('/')
    if ($first -match '^(\[[0-9A-Fa-f:]+\]|[A-Za-z0-9.\-]+)(:(\d{1,5}))?$') {
        $result.HostName = $Matches[1].Trim('[', ']')
        $port = 80
        if ($Matches[3]) { $port = [int]$Matches[3] }
        if ($port -ge 1 -and $port -le 65535) { $result.Port = $port }
    }
    return $result
}
function Get-UpdateServiceState {
    param([Parameter(Mandatory)][string]$Name)
    try { return Get-Service -Name $Name -ErrorAction Stop }
    catch { return $null }
}
function Stop-UpdateService {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-UpdateServiceState -Name $Name
    if ($null -eq $svc) { Write-Log "Service not present: $Name"; return $true }
    if ($svc.Status -eq 'Stopped') { Write-Log "Service already stopped: $Name"; return $true }
    try {
        Write-Log "Stopping service: $Name"
        Stop-Service -Name $Name -Force -ErrorAction Stop
        $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
        return $true
    }
    catch {
        $svc.Refresh()
        if ($svc.Status -eq 'Stopped') { return $true }
        Write-Log "Could not stop ${Name} (status $($svc.Status)): $($_.Exception.Message)" -Level WARN
        return $false
    }
}
function Start-UpdateService {
    param([Parameter(Mandatory)][string]$Name)
    $svc = Get-UpdateServiceState -Name $Name
    if ($null -eq $svc) { return }
    if ($svc.StartType -eq 'Disabled') { Write-Log "Not starting disabled service: $Name" -Level WARN; return }
    if ($svc.Status -eq 'Running') { Write-Log "Service already running: $Name"; return }
    try {
        Write-Log "Starting service: $Name"
        Start-Service -Name $Name -ErrorAction Stop
        $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
    }
    catch {
        Add-Failure "Could not start ${Name}: $($_.Exception.Message)"
    }
}
function Rename-UpdateStore {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Stamp)
    if (-not (Test-Path -LiteralPath $Path)) { Write-Log "Not found, skipped: $Path"; return $true }
    $item = Get-Item -LiteralPath $Path -Force
    if (Test-IsReparsePoint $item) { Add-Failure "Refusing to rename reparse point: $Path"; return $false }
    $parent  = Split-Path -Path $Path -Parent
    $newLeaf = '{0}.bak.{1}' -f $item.Name, $Stamp
    if (Test-Path -LiteralPath (Join-Path $parent $newLeaf)) {
        $newLeaf = '{0}.bak.{1}-{2}' -f $item.Name, $Stamp, [Guid]::NewGuid().ToString('N').Substring(0, 4)
    }
    try {
        Rename-Item -LiteralPath $Path -NewName $newLeaf -ErrorAction Stop
        Write-Log "Renamed: $Path -> $(Join-Path $parent $newLeaf)"
        return $true
    }
    catch {
        Write-Log "Rename failed for ${Path}: $($_.Exception.Message)" -Level WARN
        return $false
    }
}
function Remove-OldStoreBackup {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][int]$Keep)
    $parent = Split-Path -Path $Path -Parent
    $leaf   = Split-Path -Path $Path -Leaf
    $pattern = '^{0}\.bak\.\d{{8}}-\d{{6}}(-[0-9a-f]{{4}})?$' -f [regex]::Escape($leaf)
    $backups = @(Get-ChildItem -LiteralPath $parent -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match $pattern } |
        Sort-Object -Property Name -Descending)
    foreach ($old in ($backups | Select-Object -Skip $Keep)) {
        # Never recurse into a junction: Remove-Item in 5.1 can delete the target's contents.
        if (Test-IsReparsePoint $old) { Write-Log "Skipped reparse point backup: $($old.FullName)" -Level WARN; continue }
        try {
            Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction Stop
            Write-Log "Removed old backup: $($old.FullName)"
        }
        catch {
            Write-Log "Could not remove old backup $($old.FullName): $($_.Exception.Message)" -Level WARN
        }
    }
}
try {
    # ---------------- Settings validation ----------------
    foreach ($name in @('ResetWinHttpProxy', 'ResetWinsock', 'ResetPolicy', 'SkipDISM', 'SkipSFC', 'SkipScan')) {
        $v = Get-Variable -Name $name -ValueOnly
        if ($v -isnot [bool]) { Stop-Repair -Code 2 -Message "Setting `$$name must be `$true or `$false." }
    }
    if ($KeepBackups -isnot [int] -or $KeepBackups -lt 1 -or $KeepBackups -gt 10) {
        Stop-Repair -Code 2 -Message 'Setting $KeepBackups must be a whole number from 1 to 10.'
    }
    if ($ServiceTimeoutSeconds -isnot [int] -or $ServiceTimeoutSeconds -lt 5 -or $ServiceTimeoutSeconds -gt 300) {
        Stop-Repair -Code 2 -Message 'Setting $ServiceTimeoutSeconds must be a whole number from 5 to 300.'
    }
    $RepairSourceArgs = @()
    if ($RepairSource -isnot [string]) { Stop-Repair -Code 2 -Message 'Setting $RepairSource must be a string.' }
    $src = $RepairSource.Trim()
    if ($src) {
        if ($src.Length -gt 260 -or $src -match '["<>|*?\r\n\t]') {
            Stop-Repair -Code 2 -Message "RepairSource is too long or contains characters that are not allowed: $src"
        }
        if ($src -match '^(?i)(wim|esd):([A-Za-z]:\\.+\.(wim|esd)|\\\\[^\\]+\\.+\.(wim|esd)):(\d{1,3})$') {
            $imagePath = $Matches[2]
            if (-not (Test-Path -LiteralPath $imagePath -PathType Leaf)) { Stop-Repair -Code 2 -Message "RepairSource image not found: $imagePath" }
        }
        elseif ($src -match '^([A-Za-z]:\\|\\\\[^\\]+\\[^\\]+)') {
            if (-not (Test-Path -LiteralPath $src -PathType Container)) { Stop-Repair -Code 2 -Message "RepairSource folder not found: $src" }
        }
        else {
            Stop-Repair -Code 2 -Message 'RepairSource must be WIM:<path>:<index>, ESD:<path>:<index>, or an existing folder path.'
        }
        $RepairSourceArgs = @("/Source:$src", '/LimitAccess')
    }
    # ---------------- Host checks ----------------
    $windowsDir = [Environment]::GetFolderPath('Windows')
    # A 32-bit host on 64-bit Windows (common with RMM agents and the x86 ISE)
    # is redirected to SysWOW64, which breaks sfc and targets the wrong catroot2.
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $nativePs = Join-Path $windowsDir 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'
        if (-not $RunFromFile) { Stop-Repair -Code 2 -Message 'This is 32-bit PowerShell. Paste into 64-bit Windows PowerShell (not the x86 version).' }
        if (-not (Test-Path -LiteralPath $nativePs -PathType Leaf)) { Stop-Repair -Code 2 -Message 'Running in 32-bit PowerShell and the 64-bit host could not be found.' }
        try {
            $proc = Start-Process -FilePath $nativePs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)) -Wait -PassThru -NoNewWindow
            $state.ExitCode = $proc.ExitCode
            throw $AbortToken
        }
        catch {
            if ($_.Exception.Message -eq $AbortToken) { throw }
            Stop-Repair -Code 2 -Message "Failed to relaunch in 64-bit PowerShell: $($_.Exception.Message)"
        }
    }
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        if (-not $RunFromFile) { Stop-Repair -Code 2 -Message 'Not elevated. Open Windows PowerShell with "Run as administrator" and paste again.' }
        $psExe = Join-Path ([Environment]::SystemDirectory) 'WindowsPowerShell\v1.0\powershell.exe'
        try {
            # -NoExit keeps the elevated window open so the summary stays visible.
            $proc = Start-Process -FilePath $psExe -Verb RunAs -ArgumentList @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $PSCommandPath)) -PassThru
            Write-Host 'Continuing in an elevated window.' -ForegroundColor Yellow
            $state.ExitCode = 0
            throw $AbortToken
        }
        catch {
            if ($_.Exception.Message -eq $AbortToken) { throw }
            Stop-Repair -Code 2 -Message "Elevation was cancelled or failed: $($_.Exception.Message)"
        }
    }
    # ---------------- Secure log ----------------
    $system32 = [Environment]::SystemDirectory
    $stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
    try {
        $state.LogDir = Initialize-LogDirectory
        $state.Suffix = [Guid]::NewGuid().ToString('N').Substring(0, 6)
        $logPath = Join-Path $state.LogDir "WURepair-$stamp-$($state.Suffix).log"
        New-ExclusiveFile -Path $logPath
        $state.LogFile = $logPath
    }
    catch {
        Stop-Repair -Code 2 -Message "Cannot use a secure log location: $($_.Exception.Message)"
    }
    foreach ($w in @($Warnings)) { Write-Log $w -Level WARN }
    Write-Log '=== Windows Update repair started ==='
    Write-Log ("Computer: {0} | OS: {1} | PowerShell: {2} | Host: {3} | Log: {4}" -f $env:COMPUTERNAME, [Environment]::OSVersion.VersionString, $PSVersionTable.PSVersion, $Host.Name, $state.LogFile)
    # ---------------- Discovery ----------------
    if ((Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
        (Test-Path -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        Add-Warning 'A reboot is already pending. If this repair does not help, reboot and run it again.'
    }
    $wuPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
    $auPolicyPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU'
    $usingWSUS = $false
    $wsusUri   = $null
    $wuServer    = Get-RegistryValue -Path $wuPolicyPath -Name 'WUServer'
    $useWUServer = Get-RegistryValue -Path $auPolicyPath -Name 'UseWUServer'
    if ($wuServer -and $useWUServer -eq 1) {
        $parsed = $null
        if ([Uri]::TryCreate([string]$wuServer, [UriKind]::Absolute, [ref]$parsed) -and $parsed.Scheme -in @('http', 'https')) {
            $usingWSUS = $true
            $wsusUri   = $parsed
        }
        else {
            Add-Warning "WUServer policy value is not a valid http/https URL: $wuServer"
        }
    }
    elseif ($wuServer) {
        Write-Log "WUServer is set ($wuServer) but UseWUServer is not 1, so WSUS is not in use."
    }
    Write-Log ("WSUS in use: {0}" -f $usingWSUS)
    if ($usingWSUS) { Write-Log "WSUS server: $($wsusUri.AbsoluteUri)" }
    $winHttpProxy = Get-WinHttpProxy
    if (-not $winHttpProxy.Known) {
        Add-Warning 'Could not parse the WinHTTP proxy setting from the registry.'
    }
    elseif ($winHttpProxy.Configured) {
        Write-Log "WinHTTP proxy: $($winHttpProxy.Server)"
        Write-Log "WinHttpSettings (backup): $($winHttpProxy.RawHex)" -FileOnly
    }
    else {
        Write-Log 'WinHTTP proxy: direct access'
    }
    # Connectivity checks are diagnostic only and do not fail the run. Direct TCP
    # tests bypass the WinHTTP proxy, so a failure behind a proxy can be expected.
    $targets = New-Object System.Collections.Generic.List[object]
    if ($usingWSUS) {
        $targets.Add([pscustomobject]@{ Host = $wsusUri.Host; Port = $wsusUri.Port; Role = 'WSUS' })
    }
    else {
        $targets.Add([pscustomobject]@{ Host = 'fe3.delivery.mp.microsoft.com'; Port = 443; Role = 'Microsoft Update' })
        $targets.Add([pscustomobject]@{ Host = 'sls.update.microsoft.com';      Port = 443; Role = 'Microsoft Update' })
        $targets.Add([pscustomobject]@{ Host = 'download.windowsupdate.com';    Port = 80;  Role = 'Microsoft Update content' })
    }
    if ($winHttpProxy.Configured -and $winHttpProxy.HostName -and $winHttpProxy.Port -gt 0) {
        $targets.Add([pscustomobject]@{ Host = $winHttpProxy.HostName; Port = $winHttpProxy.Port; Role = 'WinHTTP proxy' })
    }
    $proxyReachable = $true
    foreach ($t in $targets) {
        $ok = Test-TcpPort -HostName $t.Host -Port $t.Port
        $level = 'INFO'
        if (-not $ok) { $level = 'WARN' }
        Write-Log ("Connectivity [{0}] {1}:{2} = {3}" -f $t.Role, $t.Host, $t.Port, $ok) -Level $level
        if ($t.Role -eq 'WinHTTP proxy' -and -not $ok) { $proxyReachable = $false }
    }
    if ($winHttpProxy.Configured -and -not $proxyReachable -and -not $ResetWinHttpProxy) {
        Add-Warning 'The configured WinHTTP proxy is unreachable. If this device does not need it, set $ResetWinHttpProxy = $true and rerun.'
    }
    # ---------------- Stop services and reset stores ----------------
    $serviceNames = @('usosvc', 'dosvc', 'wuauserv', 'bits', 'cryptsvc')
    $wasRunning = @{}
    foreach ($name in $serviceNames) {
        $svc = Get-UpdateServiceState -Name $name
        if ($null -eq $svc) { continue }
        $wasRunning[$name] = ($svc.Status -eq 'Running')
        if ($svc.StartType -eq 'Disabled' -and $name -in @('wuauserv', 'bits', 'cryptsvc')) {
            Add-Warning "Service $name is Disabled (possibly by policy). Windows Update cannot work until it is re-enabled."
        }
    }
    # Trigger-start services can come back on their own, so stop in two passes
    # and verify immediately before touching the stores.
    $state.ServicesTouched = $true
    $stopped = $true
    foreach ($name in $serviceNames) { if (-not (Stop-UpdateService -Name $name)) { $stopped = $false } }
    if (-not $stopped) {
        Start-Sleep -Seconds 3
        foreach ($name in $serviceNames) { $null = Stop-UpdateService -Name $name }
    }
    $coreRunning = @(foreach ($name in @('wuauserv', 'bits', 'cryptsvc')) {
        $s = Get-UpdateServiceState -Name $name
        if ($s -and $s.Status -ne 'Stopped') { $name }
    })
    if ($coreRunning.Count -gt 0) {
        Add-Failure "Services did not stop ($($coreRunning -join ', ')). Skipped the BITS queue and store reset to avoid a partial reset."
    }
    else {
        try {
            $downloader = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'Microsoft\Network\Downloader'
            if (Test-Path -LiteralPath $downloader -PathType Container) {
                $qmgr = @(Get-ChildItem -LiteralPath $downloader -Filter 'qmgr*.dat' -File -Force -ErrorAction Stop |
                    Where-Object { -not (Test-IsReparsePoint $_) })
                foreach ($f in $qmgr) { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop }
                Write-Log "Cleared BITS queue files: $($qmgr.Count)"
            }
        }
        catch {
            Add-Failure "Failed clearing BITS queue: $($_.Exception.Message)"
        }
        $softwareDistribution = Join-Path $windowsDir 'SoftwareDistribution'
        $catroot2 = Join-Path $system32 'catroot2'
        if (Rename-UpdateStore -Path $softwareDistribution -Stamp $stamp) {
            Remove-OldStoreBackup -Path $softwareDistribution -Keep $KeepBackups
        }
        else {
            Add-Failure "Could not reset $softwareDistribution"
        }
        # Cryptographic Services is frequently restarted by other callers.
        $catOk = Rename-UpdateStore -Path $catroot2 -Stamp $stamp
        if (-not $catOk) {
            $null = Stop-UpdateService -Name 'cryptsvc'
            $catOk = Rename-UpdateStore -Path $catroot2 -Stamp $stamp
        }
        if ($catOk) { Remove-OldStoreBackup -Path $catroot2 -Keep $KeepBackups }
        else { Add-Failure "Could not reset $catroot2" }
    }
    # ---------------- Optional network resets ----------------
    $netsh = Join-Path $system32 'netsh.exe'
    if ($ResetWinHttpProxy) {
        if ($usingWSUS) { Add-Warning 'Resetting the WinHTTP proxy on a WSUS client. Confirm the WSUS server is reachable without a proxy.' }
        $code = Invoke-NativeCommand -FilePath $netsh -ArgumentList @('winhttp', 'reset', 'proxy')
        if ($code -eq 0) { Write-Log 'WinHTTP proxy reset to direct access.' }
        else { Add-Failure "netsh winhttp reset proxy failed: $(Format-ExitCode $code)" }
        $code = Invoke-NativeCommand -FilePath $netsh -ArgumentList @('winhttp', 'reset', 'autoproxy')
        if ($code -eq 0) { Write-Log 'WinHTTP autoproxy service reset.' }
        else { Add-Warning "netsh winhttp reset autoproxy not supported or failed on this build: $(Format-ExitCode $code)" }
    }
    if ($ResetWinsock) {
        $code = Invoke-NativeCommand -FilePath $netsh -ArgumentList @('winsock', 'reset')
        if ($code -eq 0) { Write-Log 'Winsock reset completed.'; $state.RebootRequired = $true }
        else { Add-Failure "netsh winsock reset failed: $(Format-ExitCode $code)" }
    }
    $code = Invoke-NativeCommand -FilePath (Join-Path $system32 'ipconfig.exe') -ArgumentList @('/flushdns')
    if ($code -eq 0) { Write-Log 'Flushed DNS cache.' }
    else { Add-Warning "ipconfig /flushdns failed: $(Format-ExitCode $code)" }
    # ---------------- Optional policy reset ----------------
    if ($ResetPolicy) {
        $partOfDomain = $false
        try { $partOfDomain = [bool](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).PartOfDomain }
        catch { Add-Warning "Could not determine domain membership: $($_.Exception.Message)" }
        if (-not $partOfDomain) {
            Add-Failure 'ResetPolicy refused: device is not domain joined, so Group Policy would not reapply the keys. Intune settings live in PolicyManager and are not affected by this option.'
        }
        else {
            $reg = Join-Path $system32 'reg.exe'
            $policyKeys = @(
                @{ Reg = 'HKLM\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate';                PS = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' },
                @{ Reg = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate'; PS = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\WindowsUpdate' }
            )
            $index = 0
            foreach ($k in $policyKeys) {
                $index++
                if (-not (Test-Path -LiteralPath $k.PS)) { Write-Log "Policy key not present: $($k.Reg)"; continue }
                $backup = Join-Path $state.LogDir ("PolicyBackup-$stamp-$index.reg")
                if (Test-Path -LiteralPath $backup) { Add-Failure "Backup path already exists, not deleting $($k.Reg)"; continue }
                $code = Invoke-NativeCommand -FilePath $reg -ArgumentList @('export', $k.Reg, $backup)
                if ($code -ne 0 -or -not (Test-Path -LiteralPath $backup -PathType Leaf)) {
                    Add-Failure "Backup of $($k.Reg) failed ($(Format-ExitCode $code)); key was not deleted."
                    continue
                }
                try {
                    Remove-Item -LiteralPath $k.PS -Recurse -Force -ErrorAction Stop
                    Write-Log "Deleted policy key $($k.Reg) (backup: $backup)"
                }
                catch {
                    Add-Failure "Failed deleting $($k.Reg): $($_.Exception.Message)"
                }
            }
            $code = Invoke-NativeCommand -FilePath (Join-Path $system32 'gpupdate.exe') -ArgumentList @('/target:computer', '/force', '/wait:120')
            if ($code -eq 0) { Write-Log 'Computer policy reapplied (gpupdate).' }
            else { Add-Failure "gpupdate failed: $(Format-ExitCode $code). Restore keys from the .reg backups if needed." }
        }
    }
    # ---------------- Restart services ----------------
    foreach ($name in @('cryptsvc', 'bits', 'wuauserv')) { Start-UpdateService -Name $name }
    foreach ($name in @('dosvc', 'usosvc')) {
        if ($wasRunning.ContainsKey($name) -and $wasRunning[$name]) { Start-UpdateService -Name $name }
    }
    # ---------------- DISM and SFC ----------------
    if (-not $SkipDISM) {
        $dismArgs = @('/Online', '/Cleanup-Image', '/RestoreHealth') + $RepairSourceArgs
        Write-Log ("Running DISM {0} (this can take a while)" -f ($dismArgs -join ' '))
        try {
            $code = Invoke-NativeCommand -FilePath (Join-Path $system32 'Dism.exe') -ArgumentList $dismArgs
            $hex = '0x{0:X8}' -f $code
            switch ($hex) {
                '0x00000000' { Write-Log 'DISM completed successfully.' }
                '0x00000BC2' { Write-Log 'DISM completed; a reboot is required.'; $state.RebootRequired = $true }
                '0x800F081F' { Add-Failure 'DISM could not find repair source files (0x800F081F). Set $RepairSource to matching install media and rerun.' }
                '0x800F0954' { Add-Failure 'DISM could not reach Windows Update for repair content (0x800F0954), which is typical on WSUS clients. Set $RepairSource, or enable the "Specify settings for optional component installation and component repair" policy with direct download from Windows Update.' }
                '0x800F0906' { Add-Failure 'DISM could not download repair content (0x800F0906). Check connectivity/proxy, or set $RepairSource.' }
                default      { Add-Failure "DISM failed: $(Format-ExitCode $code). See $(Join-Path $windowsDir 'Logs\DISM\dism.log')" }
            }
        }
        catch {
            Add-Failure "DISM could not run: $($_.Exception.Message)"
        }
    }
    if (-not $SkipSFC) {
        Write-Log 'Running sfc /scannow (this can take a while)'
        try {
            # sfc writes UTF-16 output; decode it as Unicode so the log is readable.
            $code = Invoke-NativeCommand -FilePath (Join-Path $system32 'sfc.exe') -ArgumentList @('/scannow') -UnicodeOutput
            $cbsLog = Join-Path $windowsDir 'Logs\CBS\CBS.log'
            if ($code -eq 0) { Write-Log "SFC completed. Details: $cbsLog" }
            else { Add-Warning "SFC returned $(Format-ExitCode $code). Review $cbsLog for [SR] entries." }
        }
        catch {
            Add-Failure "SFC could not run: $($_.Exception.Message)"
        }
    }
    # ---------------- Diagnostics and scan ----------------
    if (-not $SkipScan) {
        if (Get-Command -Name Get-WindowsUpdateLog -ErrorAction SilentlyContinue) {
            $wuReadableLog = Join-Path $state.LogDir "WindowsUpdate-$stamp-$($state.Suffix).log"
            try {
                if (Test-Path -LiteralPath $wuReadableLog) { throw "Target already exists: $wuReadableLog" }
                Get-WindowsUpdateLog -LogPath $wuReadableLog -ErrorAction Stop *> $null
                if (Test-Path -LiteralPath $wuReadableLog -PathType Leaf) { Write-Log "Readable Windows Update log: $wuReadableLog" }
                else { Add-Warning 'Get-WindowsUpdateLog finished but produced no file.' }
            }
            catch {
                Add-Warning "Get-WindowsUpdateLog failed: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log 'Get-WindowsUpdateLog is not available in this PowerShell host; skipped.'
        }
        # UsoClient is undocumented; treat it as best effort only.
        $uso = Join-Path $system32 'UsoClient.exe'
        if (Test-Path -LiteralPath $uso -PathType Leaf) {
            try {
                Start-Process -FilePath $uso -ArgumentList 'StartScan' -WindowStyle Hidden -ErrorAction Stop
                Write-Log 'Requested an update scan (UsoClient StartScan, best effort).'
            }
            catch {
                Add-Warning "Could not request an update scan: $($_.Exception.Message)"
            }
        }
        else {
            Write-Log 'UsoClient.exe not found; open Settings > Windows Update to start a scan.'
        }
    }
    # ---------------- Summary ----------------
    Write-Log '=== Repair complete ==='
    Write-Log ("Failures: {0} | Warnings: {1}" -f $Failures.Count, $Warnings.Count)
    foreach ($f in $Failures) { Write-Log "  FAILED: $f" -Level ERROR -FileOnly }
    foreach ($w in $Warnings) { Write-Log "  WARNING: $w" -Level WARN -FileOnly }
    Write-Host ''
    if ($Failures.Count -eq 0) { Write-Host 'Repair finished without failures.' -ForegroundColor Green }
    else {
        Write-Host 'Repair finished with failures:' -ForegroundColor Red
        foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Red }
    }
    if ($Warnings.Count -gt 0) {
        Write-Host 'Warnings:' -ForegroundColor Yellow
        foreach ($w in $Warnings) { Write-Host "  - $w" -ForegroundColor Yellow }
    }
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Green
    if ($state.RebootRequired) { Write-Host '1. Reboot the workstation (required).' } else { Write-Host '1. Reboot the workstation (recommended).' }
    Write-Host '2. Open Settings > Windows Update > Check for updates.'
    Write-Host "3. Review the log: $($state.LogFile)"
    if ($usingWSUS) {
        Write-Host "WSUS server: $($wsusUri.AbsoluteUri) - if updates still fail, confirm the device can reach it on port $($wsusUri.Port)." -ForegroundColor Yellow
    }
    else {
        Write-Host 'If updates still fail, verify outbound access to Microsoft Update endpoints over HTTP/HTTPS.' -ForegroundColor Yellow
    }
    if ($Failures.Count -gt 0) { $state.ExitCode = 1 } else { $state.ExitCode = 0 }
}
catch {
    if ($_.Exception.Message -ne $AbortToken) {
        # Unexpected error: report it instead of letting it escape.
        $state.ExitCode = 1
        $detail = "Unexpected error at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
        if ($state.LogFile) { Write-Log $detail -Level ERROR } else { Write-Host $detail -ForegroundColor Red }
        if ($state.ServicesTouched) {
            Write-Host 'Update services may still be stopped. Run: Start-Service cryptsvc, bits, wuauserv' -ForegroundColor Yellow
        }
    }
}
# Pasted: never call exit (it would close the window); report through $LASTEXITCODE.
# As a file: exit with the code so Intune / RMM can read it.
if ($RunFromFile) { exit $state.ExitCode }
$global:LASTEXITCODE = $state.ExitCode
}
