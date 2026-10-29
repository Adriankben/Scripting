# winget on Windows Server 2019

Microsoft doesn't officially support winget on Server 2019, but it runs there. These scripts install it from Microsoft sources only, test it, and can roll it back.

| Script | Purpose |
|---|---|
| `Install-WinGet-Server2019.ps1` | Installs App Installer (winget), its dependencies and the VC++ runtime, then tests winget |
| `Uninstall-WinGet-Server2019.ps1` | Removes only what the install added, using the state file it saved |

## Usage

Run from an elevated PowerShell. Test on one server first.

```powershell
# Stage once on a machine with internet (writes hashes.json and prints its SHA256)
.\Install-WinGet-Server2019.ps1 -StageTo \\fileserver\software\winget -Version v1.29.380

# Deploy offline from the share (recommended for fleets)
.\Install-WinGet-Server2019.ps1 -SourcePath \\fileserver\software\winget -ManifestHash <sha256 of hashes.json>

# Or install a single server straight from GitHub
.\Install-WinGet-Server2019.ps1 -Version v1.29.380 [-Proxy http://proxy:8080]

# Roll back (preview first)
.\Uninstall-WinGet-Server2019.ps1 -WhatIf
.\Uninstall-WinGet-Server2019.ps1 [-RemoveVCRedist]
```

Exit codes: `0` installed and all tests passed, `1` install failed, `2` installed but a test failed. Logs, downloads, the permissions backup and the rollback state file are kept in `C:\ProgramData\WinGetInstall`.

## Supply-chain controls

- Files come only from the `microsoft/winget-cli` GitHub releases and `aka.ms` (VC++ runtime). No third-party scripts or modules are used.
- The App Installer bundle, every dependency package and the VC++ installer must carry a valid Microsoft Corporation Authenticode signature.
- Online downloads are checked against the SHA256 digests GitHub publishes. Offline installs check every file against `hashes.json`, and `hashes.json` against `-ManifestHash`.
- Files are copied from the share before they're checked and installed, so the share can't change mid-install. Make the share read-only for the install accounts.

## Security change: WindowsApps folder permission

Server 2019 blocks running `winget.exe` by its full path, even for administrators. SYSTEM, RMM agents and scheduled tasks need to do exactly that. When the script detects the block, it:

1. Takes ownership of the winget package folder only (`C:\Program Files\WindowsApps\Microsoft.DesktopAppInstaller_<version>_x64__8wekyb3d8bbwe`) with `takeown`, falling back to `icacls` with the Administrators SID on non-English Windows.
2. Saves the original permissions with `icacls /save`.
3. Grants `BUILTIN\Administrators` Read & Execute. No write access is granted.
4. Sets the owner back to `NT SERVICE\TrustedInstaller`.

The rollback script restores the saved permissions.

## Using winget on servers

Add `--source winget` to skip the Microsoft Store source, which fails on Server:

```powershell
winget list --upgrade-available --source winget
winget show --id <id>          # check the publisher and installer URL first
winget upgrade --id <id> --exact --source winget --silent --accept-package-agreements --accept-source-agreements
```
