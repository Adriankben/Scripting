# ============================================================================
# LAB USE ONLY - DO NOT RUN IN PRODUCTION
# Grants the 'Everyone' group Full Control (and, in the .ps1, ownership) over a
# folder tree. This deliberately creates an insecure configuration and is meant
# only for isolated test labs, e.g. to reproduce permission issues or to build
# vulnerable targets for detection and remediation practice.
# ============================================================================

$paths = @(
    "C:\Path"
)

foreach ($path in $paths) {
    if (Test-Path $path) {
        icacls "$path" /grant Everyone:(OI)(CI)F /T /C
    } else {
        Write-Host "Path not found: $path"
    }
}
