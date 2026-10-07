# ============================================================
# Enterprise WinGet Application Updates
# Updates all WinGet applications EXCEPT Java/JDK/JRE packages
# Recommended execution context: SYSTEM / Elevated
# ============================================================

$ErrorActionPreference = "Continue"

# -----------------------------
# Logging
# -----------------------------
$LogRoot = "C:\ProgramData\WingetEnterprise"
$LogFile = "$LogRoot\WingetUpdate.log"

if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

Start-Transcript -Path $LogFile -Append

Write-Host ""
Write-Host "============================================="
Write-Host " Enterprise WinGet Update"
Write-Host " Started: $(Get-Date)"
Write-Host "============================================="
Write-Host ""

# -----------------------------
# Locate winget.exe
# -----------------------------
$Winget = $null

$WingetCommand = Get-Command winget.exe -ErrorAction SilentlyContinue

if ($WingetCommand) {
    $Winget = $WingetCommand.Source
}
else {
    $DesktopAppInstaller = Get-AppxPackage `
        -AllUsers `
        -Name Microsoft.DesktopAppInstaller `
        -ErrorAction SilentlyContinue |
        Sort-Object Version -Descending |
        Select-Object -First 1

    if ($DesktopAppInstaller) {
        $PossibleWinget = Join-Path `
            $DesktopAppInstaller.InstallLocation `
            "winget.exe"

        if (Test-Path $PossibleWinget) {
            $Winget = $PossibleWinget
        }
    }
}

if (-not $Winget) {
    Write-Error "WinGet could not be located."
    Stop-Transcript
    exit 1
}

Write-Host "WinGet found:"
Write-Host $Winget
Write-Host ""

# -----------------------------
# Update WinGet sources
# -----------------------------
Write-Host "Updating WinGet sources..."

& $Winget source update --disable-interactivity

Write-Host ""

# -----------------------------
# Discover available upgrades
# -----------------------------
Write-Host "Scanning for available upgrades..."

$UpgradeOutput = & $Winget upgrade `
    --accept-source-agreements `
    --disable-interactivity 2>&1

$UpgradeOutput | ForEach-Object {
    Write-Host $_
}

Write-Host ""

# -----------------------------
# Java detection
#
# Covers common Java distributions:
# Oracle Java
# OpenJDK
# Eclipse Temurin
# Amazon Corretto
# Azul Zulu
# BellSoft Liberica
# IBM Semeru
# GraalVM
# SAPMachine
# -----------------------------

$JavaPattern = '(?i)\b(java|jdk|jre|openjdk|temurin|corretto|zulu|liberica|semeru|graalvm|sapmachine)\b'

$JavaIDs = foreach ($Line in $UpgradeOutput) {

    $Text = [string]$Line

    if ($Text -match $JavaPattern) {

        # WinGet columns are normally separated by 2+ spaces
        $Columns = $Text.Trim() -split '\s{2,}'

        if ($Columns.Count -ge 2) {

            $CandidateID = $Columns[1].Trim()

            # Basic validation of WinGet package ID
            if (
                $CandidateID -match '^[A-Za-z0-9][A-Za-z0-9._+\-]*$' -and
                $CandidateID -notmatch '^(ID|Id)$'
            ) {
                $CandidateID
            }
        }
    }
}

$JavaIDs = $JavaIDs |
    Sort-Object -Unique

# -----------------------------
# Block Java upgrades
# -----------------------------
if ($JavaIDs) {

    Write-Host "Java packages detected."
    Write-Host "Applying blocking pins..."
    Write-Host ""

    foreach ($PackageID in $JavaIDs) {

        Write-Host "Protecting: $PackageID"

        & $Winget pin add `
            --id $PackageID `
            --exact `
            --blocking `
            --accept-source-agreements `
            --disable-interactivity

        Write-Host ""
    }

}
else {
    Write-Host "No Java packages with pending upgrades detected."
}

# -----------------------------
# Display current pins
# -----------------------------
Write-Host ""
Write-Host "Current WinGet pins:"
Write-Host "--------------------"

& $Winget pin list --disable-interactivity

Write-Host ""

# -----------------------------
# Upgrade everything else
# -----------------------------
Write-Host "Starting application upgrades..."
Write-Host ""

& $Winget upgrade `
    --all `
    --silent `
    --accept-package-agreements `
    --accept-source-agreements `
    --disable-interactivity

$WingetExitCode = $LASTEXITCODE

Write-Host ""
Write-Host "============================================="
Write-Host " WinGet update completed"
Write-Host " Exit Code: $WingetExitCode"
Write-Host " Completed: $(Get-Date)"
Write-Host "============================================="

Stop-Transcript

exit $WingetExitCode