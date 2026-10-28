<#
.SYNOPSIS
    Installs winget (App Installer) on Windows Server 2019, then tests it.

.DESCRIPTION
    Microsoft sources only: App Installer and its dependency pack come from the official
    microsoft/winget-cli GitHub release, the VC++ runtime from aka.ms. Every file is checked for a
    valid Microsoft Authenticode signature and, where a hash is known, its SHA256.

    Three ways to run it:

      STAGE (once, on a machine with internet):
          .\Install-WinGet-Server2019.ps1 -StageTo \\fileserver\software\winget -Version v1.29.380
        Downloads the pinned release + VC++ runtime, verifies them, writes hashes.json and prints the
        SHA256 of hashes.json. Review, then lock the share down to read-only for servers.

      OFFLINE / FLEET (recommended for enterprise):
          .\Install-WinGet-Server2019.ps1 -SourcePath \\fileserver\software\winget -ManifestHash <sha256 of hashes.json>
        Installs only from the share. Every file must match hashes.json, and hashes.json must match
        -ManifestHash, so a tampered share is detected. No internet or GitHub API access needed.

      ONLINE (single servers):
          .\Install-WinGet-Server2019.ps1 -Version v1.29.380
        Downloads directly from GitHub. Verifies against the SHA256 digests GitHub publishes for the
        release assets when available.

    Install steps:
      1. Pre-flight checks (admin, OS build, Appx cmdlets).
      2. Records what is already installed to a state file so Uninstall-WinGet-Server2019.ps1
         only removes what this script added.
      3. Installs the Visual C++ 2015-2022 x64 redistributable if missing (winget needs it on 2019).
      4. Gets and verifies App Installer, its license and dependency pack.
      5. Provisions App Installer machine-wide and registers it for the current user.
      6. If winget.exe is blocked when run by path (normal on 2019), grants local Administrators
         read+execute on its package folder (original ACL saved for rollback), then adds it to PATH.
      7. Tests winget: --version, source update, search, show, list, upgrade (dry run).

    Logs: C:\ProgramData\WinGetInstall\install-<timestamp>.log
    Exit codes: 0 = installed and all tests passed, 1 = install failed, 2 = installed but tests failed.

.PARAMETER Version
    winget-cli release tag, e.g. "v1.29.380". Default "latest" (warns; pin a version for fleets).
.PARAMETER SourcePath
    Folder or UNC share created with -StageTo. Installs offline from it.
.PARAMETER ManifestHash
    Expected SHA256 of hashes.json in -SourcePath. Strongly recommended with -SourcePath.
.PARAMETER StageTo
    Download and verify the files into this folder, write hashes.json, then exit. Installs nothing.
.PARAMETER Proxy
    Proxy URL, e.g. http://proxy.corp.local:8080. Uses the current account's credentials.
.PARAMETER WorkDir
    Where downloads, logs and the rollback state file are kept. Keep it; the rollback script reads it.
.PARAMETER SkipTest
    Install only, do not run the tests.
#>
[CmdletBinding(DefaultParameterSetName = 'Online')]
param(
    [Parameter(ParameterSetName = 'Online')]
    [Parameter(ParameterSetName = 'Stage')]
    [string]$Version = 'latest',

    [Parameter(ParameterSetName = 'Offline', Mandatory)]
    [string]$SourcePath,

    [Parameter(ParameterSetName = 'Offline')]
    [ValidatePattern('^[0-9A-Fa-f]{64}$')]
    [string]$ManifestHash,

    [Parameter(ParameterSetName = 'Stage', Mandatory)]
    [string]$StageTo,

    [string]$Proxy,
    [string]$WorkDir = "$env:ProgramData\WinGetInstall",
    [switch]$SkipTest
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is very slow on PS 5.1 with the progress bar
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Mode = $PSCmdlet.ParameterSetName
$null = New-Item -ItemType Directory -Path $WorkDir -Force
$stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$logFile   = Join-Path $WorkDir "install-$stamp.log"
$stateFile = Join-Path $WorkDir 'rollback-state.json'
$dlDir     = Join-Path $WorkDir 'downloads'
$null = New-Item -ItemType Directory -Path $dlDir -Force
Start-Transcript -Path $logFile -Append | Out-Null

$BundleName = 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle'
$DepsName   = 'DesktopAppInstaller_Dependencies.zip'
$VCName     = 'vc_redist.x64.exe'
$VCUrl      = 'https://aka.ms/vs/17/release/vc_redist.x64.exe'

function Write-Step($msg) { Write-Host "`n=== $msg ===" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Write-Warn2($msg){ Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red }

# ---------------------------------------------------------------- web / proxy
$webArgs = @{ UseBasicParsing = $true }
if ($Proxy) {
    $webArgs.Proxy = $Proxy
    $webArgs.ProxyUseDefaultCredentials = $true
    $wp = New-Object System.Net.WebProxy($Proxy, $true)
    $wp.UseDefaultCredentials = $true
    [System.Net.WebRequest]::DefaultWebProxy = $wp
}
function Save-Url($url, $outFile) { Invoke-WebRequest -Uri $url -OutFile $outFile @webArgs }

# ---------------------------------------------------------------- verification
function Get-Sha256($path) { (Get-FileHash -Path $path -Algorithm SHA256).Hash.ToUpperInvariant() }

function Assert-MicrosoftSigned($path) {
    $sig = Get-AuthenticodeSignature $path
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation') {
        throw "Signature check failed for $(Split-Path $path -Leaf): $($sig.Status) $($sig.SignerCertificate.Subject)"
    }
}

function Assert-Hash($path, $expected) {
    $actual = Get-Sha256 $path
    if ($actual -ne $expected.ToUpperInvariant()) {
        throw "SHA256 mismatch for $(Split-Path $path -Leaf): expected $expected, got $actual"
    }
}

function Assert-LicenseXml($path) {
    # The license is unsigned XML; at least make sure it is a well-formed license file
    try { [xml]$x = Get-Content $path -Raw } catch { throw "License file is not valid XML: $path" }
    if (-not $x.DocumentElement) { throw "License file is empty: $path" }
}

# ---------------------------------------------------------------- local state helpers
function Get-VCRedistX64 {
    $key = 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64'
    if (Test-Path $key) {
        $p = Get-ItemProperty $key
        if ($p.Installed -eq 1) { return "$($p.Major).$($p.Minor).$($p.Bld)" }
    }
    return $null
}

function Get-AppxNames {
    Get-AppxPackage -AllUsers |
        Where-Object { $_.Name -in 'Microsoft.DesktopAppInstaller','Microsoft.VCLibs.140.00.UWPDesktop','Microsoft.VCLibs.140.00','Microsoft.UI.Xaml.2.8' -or $_.Name -like 'Microsoft.WindowsAppRuntime.*' } |
        Select-Object -ExpandProperty PackageFullName
}

function Find-WinGetExe {
    $pkg = Get-AppxPackage -AllUsers -Name Microsoft.DesktopAppInstaller |
           Where-Object { $_.Architecture -eq 'X64' } |
           Sort-Object { [version]$_.Version } -Descending | Select-Object -First 1
    if ($pkg) {
        $exe = Join-Path $pkg.InstallLocation 'winget.exe'
        if (Test-Path $exe) { return $exe }
    }
    $found = Resolve-Path "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*_x64__8wekyb3d8bbwe\winget.exe" -ErrorAction SilentlyContinue |
             Sort-Object Path -Descending | Select-Object -First 1
    if ($found) { return $found.Path }
    return $null
}

function Test-WinGetRuns($exe) {
    # Logs why a launch failed so the transcript shows the real error, not just "cannot run"
    if (-not $exe) { return $false }
    if (-not (Test-Path $exe)) { Write-Host "  not found: $exe"; return $false }
    try {
        $out = & $exe --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Host ("  {0} --version exited 0x{1:X8}: {2}" -f $exe, $LASTEXITCODE, $out.Trim())
        return $false
    } catch {
        Write-Host "  $exe failed to start: $($_.Exception.Message)"
        return $false
    }
}

function Grant-WinGetFolderAccess($dir, $backupFile) {
    # On Server 2019 the WindowsApps package folder denies execute to Administrators/SYSTEM when
    # winget.exe is launched by full path. Add a read+execute ACE for Administrators only, then hand
    # ownership back to TrustedInstaller. The original ACL is saved so the rollback script can restore it.
    # Ownership has to come first: Administrators can't even read the ACL until they own the folder.
    $parent = Split-Path $dir -Parent
    $ErrorActionPreference = 'Continue'   # native tools write to stderr; judge them by exit code instead

    # icacls with a SID is language-independent; takeown's /d Y only works on English Windows
    $out = & icacls.exe $dir /setowner '*S-1-5-32-544' /t /c /q 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn2 "icacls /setowner failed ($out); falling back to takeown"
        $out = & takeown.exe /f $dir /r /a /d Y 2>&1
        if ($LASTEXITCODE -ne 0) { throw "Could not take ownership of $dir (exit $LASTEXITCODE): $out" }
    }
    $out = & icacls.exe $dir /save $backupFile /t /c /q 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls save failed on $dir (exit $LASTEXITCODE): $out" }
    $out = & icacls.exe $dir /grant '*S-1-5-32-544:(OI)(CI)(RX)' /t /c /q 2>&1
    if ($LASTEXITCODE -ne 0) { throw "icacls grant failed on $dir (exit $LASTEXITCODE): $out" }
    $out = & icacls.exe $dir /setowner 'NT SERVICE\TrustedInstaller' /t /c /q 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "Could not hand ownership back to TrustedInstaller: $out" }
    Write-Host "  Folder ACL after the change:"
    & icacls.exe $dir 2>&1 | ForEach-Object { Write-Host "    $_" }
    return $parent
}

# ---------------------------------------------------------------- getting the files
function Get-ReleaseFiles($tag, $destDir) {
    # Downloads bundle, license and dependency pack for a winget-cli release into $destDir.
    # Returns @{ Tag; Files = @{ name = sha256 } } after signature + GitHub digest checks.
    $api = if ($tag -eq 'latest') { 'https://api.github.com/repos/microsoft/winget-cli/releases/latest' }
           else { "https://api.github.com/repos/microsoft/winget-cli/releases/tags/$tag" }
    $headers = @{ 'User-Agent' = 'Install-WinGet-Server2019' }
    if ($env:GITHUB_TOKEN) { $headers.Authorization = "Bearer $env:GITHUB_TOKEN" }   # avoids the 60/hour anonymous API limit
    $release = Invoke-RestMethod -Uri $api -Headers $headers @webArgs
    Write-Host "Release: $($release.tag_name) ($($release.published_at))"

    $assets = @(
        $release.assets | Where-Object name -eq   $BundleName    | Select-Object -First 1
        $release.assets | Where-Object name -like '*License1.xml' | Select-Object -First 1
        $release.assets | Where-Object name -eq   $DepsName      | Select-Object -First 1
    )
    if (@($assets | Where-Object { $_ }).Count -ne 3) { throw "Release $($release.tag_name) is missing the bundle, license or dependency asset." }

    $files = @{}
    foreach ($a in $assets) {
        $out = Join-Path $destDir $a.name
        Write-Host "  $($a.name)"
        Save-Url $a.browser_download_url $out
        if ($a.digest -match '^sha256:([0-9a-fA-F]{64})$') {
            Assert-Hash $out $Matches[1]
            Write-Ok "  SHA256 matches GitHub's published digest"
        } else {
            Write-Warn2 '  GitHub published no digest for this asset; relying on the signature check'
        }
        $files[$a.name] = Get-Sha256 $out
    }
    Assert-MicrosoftSigned (Join-Path $destDir $BundleName)
    Assert-LicenseXml (Join-Path $destDir ($assets[1].name))
    return @{ Tag = $release.tag_name; Files = $files }
}

# ================================================================ STAGE MODE
if ($Mode -eq 'Stage') {
    try {
        Write-Step "Staging winget '$Version' to $StageTo"
        if ($Version -eq 'latest') { Write-Warn2 'Staging "latest". The exact tag is recorded in hashes.json.' }
        $null = New-Item -ItemType Directory -Path $StageTo -Force
        $rel = Get-ReleaseFiles $Version $StageTo

        Write-Host "  $VCName"
        $vcOut = Join-Path $StageTo $VCName
        Save-Url $VCUrl $vcOut
        Assert-MicrosoftSigned $vcOut
        $rel.Files[$VCName] = Get-Sha256 $vcOut

        $manifest = [ordered]@{
            Version  = $rel.Tag
            Created  = (Get-Date).ToString('s')
            StagedBy = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            Files    = $rel.Files
        }
        $manifestPath = Join-Path $StageTo 'hashes.json'
        $manifest | ConvertTo-Json -Depth 5 | Set-Content $manifestPath -Encoding UTF8
        $mh = Get-Sha256 $manifestPath

        Write-Step 'Staged'
        $rel.Files.GetEnumerator() | ForEach-Object { Write-Host ("  {0}  {1}" -f $_.Value, $_.Key) }
        Write-Host "`nhashes.json SHA256: $mh" -ForegroundColor Green
        Write-Host "Deploy with:`n  .\Install-WinGet-Server2019.ps1 -SourcePath '$StageTo' -ManifestHash $mh"
        Write-Host 'Make the share read-only for the accounts that run the install.'
        Stop-Transcript | Out-Null
        exit 0
    } catch {
        Write-Fail $_.Exception.Message
        Stop-Transcript | Out-Null
        exit 1
    }
}

# ================================================================ INSTALL
$installOk = $false
try {
    # ---------------------------------------------------------------- 1. pre-flight
    Write-Step "Pre-flight checks (mode: $Mode)"
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Run this script from an elevated (Administrator) PowerShell.'
    }
    $os = Get-CimInstance Win32_OperatingSystem
    Write-Host "OS: $($os.Caption) build $($os.BuildNumber)  User: $($id.Name)"
    if ([int]$os.BuildNumber -lt 17763) { throw 'winget needs build 17763 (Server 2019 / Windows 10 1809) or later.' }
    if ([int]$os.BuildNumber -ne 17763) { Write-Warn2 'This is not Server 2019; the script should still work but was written for 2019.' }
    if (-not (Get-Command Add-AppxProvisionedPackage -ErrorAction SilentlyContinue)) {
        throw 'Appx cmdlets are missing (Server Core without Desktop Experience?). winget is not practical here.'
    }
    if ($id.IsSystem) { Write-Warn2 'Running as SYSTEM: per-user registration will be skipped, machine-wide provisioning still happens.' }
    if ($Mode -eq 'Offline' -and -not $ManifestHash) { Write-Warn2 'No -ManifestHash given: files are checked against hashes.json, but hashes.json itself is not verified.' }

    # ---------------------------------------------------------------- 2. record state for rollback
    Write-Step 'Recording current state for rollback'
    $machinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
    if (Test-Path $stateFile) {
        # Keep the ORIGINAL state from the first run so re-running doesn't hide what we added
        $state = Get-Content $stateFile -Raw | ConvertFrom-Json
        Write-Warn2 "Existing state file found from $($state.Created); keeping its original baseline."
    } else {
        $state = [pscustomobject]@{
            Created              = (Get-Date).ToString('s')
            VCRedistBefore       = Get-VCRedistX64
            VCRedistInstalledByUs= $false
            AppxBefore           = @(Get-AppxNames)
            ProvisionedBefore    = @(Get-AppxProvisionedPackage -Online | Where-Object DisplayName -eq 'Microsoft.DesktopAppInstaller' | Select-Object -ExpandProperty PackageName)
            MachinePathBefore    = $machinePath
            PathEntryAdded       = $null
        }
        $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
    }
    Write-Ok "State saved to $stateFile"
    Write-Host "Already present: VC++ x64 = $($state.VCRedistBefore); Appx = $(@($state.AppxBefore) -join ', ')"

    # ---------------------------------------------------------------- 3. get + verify files
    if ($Mode -eq 'Offline') {
        Write-Step "Copying files from $SourcePath"
        $manifestSrc = Join-Path $SourcePath 'hashes.json'
        if (-not (Test-Path $manifestSrc)) { throw "hashes.json not found in $SourcePath. Create the share with -StageTo." }
        $manifestLocal = Join-Path $dlDir 'hashes.json'
        Copy-Item $manifestSrc $manifestLocal -Force
        if ($ManifestHash) { Assert-Hash $manifestLocal $ManifestHash; Write-Ok 'hashes.json matches -ManifestHash' }
        $manifest = Get-Content $manifestLocal -Raw | ConvertFrom-Json
        Write-Host "Staged version: $($manifest.Version) (staged $($manifest.Created) by $($manifest.StagedBy))"
        $licenseName = $null
        foreach ($p in $manifest.Files.PSObject.Properties) {
            $src = Join-Path $SourcePath $p.Name
            if (-not (Test-Path $src)) { throw "$($p.Name) listed in hashes.json but missing from $SourcePath" }
            $dst = Join-Path $dlDir $p.Name
            Copy-Item $src $dst -Force       # work from a local copy so the share can't change mid-install
            Assert-Hash $dst $p.Value
            Write-Ok "$($p.Name) SHA256 OK"
            if ($p.Name -like '*License1.xml') { $licenseName = $p.Name }
        }
        if (-not $licenseName) { throw 'No license file listed in hashes.json' }
        Assert-MicrosoftSigned (Join-Path $dlDir $BundleName)
        Assert-LicenseXml (Join-Path $dlDir $licenseName)
        $vcHash = $manifest.Files.$VCName
    } else {
        Write-Step "Downloading winget release '$Version' from github.com/microsoft/winget-cli"
        $rel = Get-ReleaseFiles $Version $dlDir
        $licenseName = $rel.Files.Keys | Where-Object { $_ -like '*License1.xml' } | Select-Object -First 1
        $vcHash = $null
    }
    $bundlePath  = Join-Path $dlDir $BundleName
    $licensePath = Join-Path $dlDir $licenseName
    $depsZip     = Join-Path $dlDir $DepsName
    Write-Ok 'Files verified; msixbundle is signed by Microsoft'

    # ---------------------------------------------------------------- 4. VC++ redist
    Write-Step 'Visual C++ 2015-2022 x64 redistributable'
    $vc = Get-VCRedistX64
    if ($vc -and [version]$vc -ge [version]'14.30') {
        Write-Ok "Already installed ($vc)"
    } else {
        $vcExe = Join-Path $dlDir $VCName
        if ($Mode -eq 'Offline') {
            if (-not $vcHash) { throw "VC++ runtime is missing on this server and $VCName is not in the staged share." }
        } else {
            Save-Url $VCUrl $vcExe
        }
        Assert-MicrosoftSigned $vcExe
        $p = Start-Process $vcExe -ArgumentList '/install','/quiet','/norestart' -Wait -PassThru
        if ($p.ExitCode -notin 0,1638,3010) { throw "VC++ redist install failed with exit code $($p.ExitCode)" }
        if ($p.ExitCode -eq 3010) { Write-Warn2 'VC++ redist wants a reboot; winget usually still works before it.' }
        if (-not $state.VCRedistBefore) { $state.VCRedistInstalledByUs = $true }
        $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
        Write-Ok "Installed ($(Get-VCRedistX64))"
    }

    # ---------------------------------------------------------------- 5. install
    $depsDir = Join-Path $dlDir 'deps'
    if (Test-Path $depsDir) { Remove-Item $depsDir -Recurse -Force }
    Expand-Archive $depsZip -DestinationPath $depsDir -Force
    $depPkgs = @(Get-ChildItem $depsDir -Recurse -Include *.appx,*.msix |
                 Where-Object { $_.FullName -match '\\x64\\' -or $_.Name -match '_x64' } |
                 Select-Object -ExpandProperty FullName)
    if (-not $depPkgs) { throw "No x64 dependency packages found in $DepsName" }
    foreach ($d in $depPkgs) { Assert-MicrosoftSigned $d; Write-Host "  dep: $(Split-Path $d -Leaf) (signed)" }

    Write-Step 'Provisioning App Installer machine-wide'
    Add-AppxProvisionedPackage -Online -PackagePath $bundlePath -DependencyPackagePath $depPkgs -LicensePath $licensePath | Out-Null
    Write-Ok 'Provisioned (new user profiles get it at logon)'

    if (-not $id.IsSystem) {
        Write-Step 'Registering for the current user'
        try {
            Add-AppxPackage -Path $bundlePath -DependencyPath $depPkgs -ForceApplicationShutdown
            Write-Ok 'Registered for current user'
        } catch {
            Write-Warn2 "Per-user registration failed ($($_.Exception.Message)); will fall back to calling winget.exe by full path."
        }
    }

    # ---------------------------------------------------------------- 6. permissions + PATH
    Write-Step 'Making winget runnable by path and adding it to machine PATH'
    $wingetExe = Find-WinGetExe
    if (-not $wingetExe) { throw 'winget.exe not found under WindowsApps after install.' }
    $wingetDir = Split-Path $wingetExe -Parent

    $wingetRun = $wingetExe
    if (-not (Test-WinGetRuns $wingetExe)) {
        Write-Warn2 'winget.exe is access-denied when run by path (normal on Server 2019). Granting Administrators read/execute on its folder.'
        $aclBackup = Join-Path $WorkDir "acl-backup-$stamp.txt"
        $aclParent = Grant-WinGetFolderAccess $wingetDir $aclBackup
        $state | Add-Member -NotePropertyName AclBackupFile   -NotePropertyValue $aclBackup -Force
        $state | Add-Member -NotePropertyName AclBackupParent -NotePropertyValue $aclParent -Force
        $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
        if (Test-WinGetRuns $wingetExe) {
            Write-Ok 'winget.exe now runs by full path (works for admins and SYSTEM)'
        } else {
            $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
            if (Test-WinGetRuns $alias) {
                Write-Warn2 "Full path still blocked; using the per-user alias $alias. SYSTEM/scheduled tasks will not work yet."
                $wingetRun = $alias
            } else {
                throw 'winget.exe still cannot run after the permission fix. Check the log, then run the rollback script.'
            }
        }
    }
    $parts = $machinePath -split ';' | Where-Object { $_ -and $_ -notlike '*Microsoft.DesktopAppInstaller_*' }
    $newPath = ($parts + $wingetDir) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'Machine')
    $env:Path = "$env:Path;$wingetDir"
    $state.PathEntryAdded = $wingetDir
    $state | ConvertTo-Json -Depth 5 | Set-Content $stateFile -Encoding UTF8
    Write-Ok "winget.exe: $wingetExe"
    Write-Warn2 'The PATH entry contains the App Installer version; re-run this script when you deploy a newer winget.'

    $installOk = $true
}
catch {
    Write-Fail $_.Exception.Message
    Write-Host "To undo partial changes run: .\Uninstall-WinGet-Server2019.ps1 -WorkDir '$WorkDir'" -ForegroundColor Yellow
    Stop-Transcript | Out-Null
    exit 1
}

# -------------------------------------------------------------------- 7. tests
if ($SkipTest) { Stop-Transcript | Out-Null; exit 0 }

Write-Step 'Testing winget'
$wingetExe = $wingetRun
$results = [ordered]@{}
function Test-WinGet($name, [string[]]$wgArgs, [scriptblock]$check) {
    Write-Host "`n> winget $($wgArgs -join ' ')"
    $out = & $wingetExe @wgArgs 2>&1 | Out-String
    $code = $LASTEXITCODE
    Write-Host $out.Trim()
    $pass = ($code -eq 0) -and (& $check $out)
    $script:results[$name] = if ($pass) { 'PASS' } else { "FAIL (exit $code)" }
}

Test-WinGet 'version'      @('--version')                                                    { param($o) $o -match 'v\d+\.\d+' }
Test-WinGet 'source update'@('source','update','--name','winget','--disable-interactivity')  { param($o) $true }
Test-WinGet 'search'       @('search','--id','Microsoft.PowerShell','--exact','--source','winget','--accept-source-agreements','--disable-interactivity') { param($o) $o -match 'Microsoft\.PowerShell' }
Test-WinGet 'show'         @('show','--id','7zip.7zip','--exact','--source','winget','--accept-source-agreements','--disable-interactivity')             { param($o) $o -match '7-Zip' }
Test-WinGet 'list'         @('list','--accept-source-agreements','--disable-interactivity')  { param($o) $true }
Test-WinGet 'upgrade (dry)'@('upgrade','--source','winget','--accept-source-agreements','--disable-interactivity') { param($o) $true }

Write-Step 'Test summary'
$results.GetEnumerator() | ForEach-Object {
    if ($_.Value -eq 'PASS') { Write-Ok "$($_.Key)" } else { Write-Fail "$($_.Key): $($_.Value)" }
}
Write-Host "`nLog: $logFile"
Write-Host "Rollback state: $stateFile"
Stop-Transcript | Out-Null

if ($results.Values -contains 'PASS' -and -not ($results.Values | Where-Object { $_ -ne 'PASS' })) {
    Write-Host "`nwinget is installed and working. Use '--source winget' in scripts (the msstore source is unreliable on Server)." -ForegroundColor Green
    exit 0
}
Write-Host "`nwinget installed but some tests failed. Check the log; to undo, run .\Uninstall-WinGet-Server2019.ps1" -ForegroundColor Yellow
exit 2
