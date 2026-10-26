# Scripting

PowerShell scripts and command references for Active Directory, Windows, Exchange, and endpoint security administration, built and refined across enterprise environments.

## Highlights

- **Identity lifecycle and AD security:** user termination automation, krbtgt key rotation, LAPS admin setup, blank password attribute remediation, account lockout and "who disabled this user" investigations
- **Protocol hardening:** disable SMBv1 and enable SMBv2/v3, disable legacy SSL and weak ciphers, configure TLS client and server settings, disable Print Spooler
- **Reporting and audits:** AD and Exchange group membership reports, local admin checks, BitLocker and UAC status, installed software inventory
- **Deployment and remediation:** Automox MSI install with validation, Zscaler certificate install, Windows Update with error handling, winget install and rollback for Server 2019, Teams vulnerability remediation, WinVerifyTrust evaluation and remediation

## Layout

| Folder | Focus |
|---|---|
| `Active Directory` | User lifecycle, group reporting, Kerberos and LAPS, account investigations |
| `Exchange` | Group and membership auditing |
| `Hardening` | Protocol and cipher hardening: `SMB`, `SSL`, `TLS` |
| `Vulnerability Remediation` | Vulnerability evaluation and remediation: `WinVerifyTrust`, `Teams Removal` |
| `Windows` | Troubleshooting, investigation, updates, and system checks |
| `Deployment` | Software and certificate deployment: `Install`, `Certificates` |
| `Apps` | Per-application validation, configuration, and removal (Cisco, Java, Nvidia, Sysmon, NinjaOne, Quick Assist) |
| `Logs` | Event log collection and review |
| `Linux` / `AWS` | Linux hardening and AWS commands |
| `Lab-Only` | Intentionally insecure configurations for isolated test labs only |

## Usage

`.ps1` and `.sh` files are complete scripts. `.txt` files are command references (quick one-liners grouped under a heading) meant to be copied and run individually.

Review each script before running it and test in a non-production environment first. Most scripts need an elevated PowerShell session and the relevant modules, such as `ActiveDirectory`.

## License

GPL-3.0
