# Define log file path - this ensures it works regardless of the profile or OneDrive setup
$logFile = "$env:USERPROFILE\Desktop\SystemRepairLog.txt"

# Check if the Desktop directory exists, create log file in a valid location if necessary
if (-not (Test-Path -Path $logFile)) {
    New-Item -ItemType File -Path $logFile -Force
}

$startTime = Get-Date

# Log the start time
Add-Content -Path $logFile -Value "Repair Process Started: $startTime"
Add-Content -Path $logFile -Value "========================="

# Run DISM to restore system health
Write-Host "Running DISM to restore system health..."
Add-Content -Path $logFile -Value "Running DISM command: DISM /Online /Cleanup-Image /RestoreHealth"
$dismResult = Start-Process -FilePath "DISM" -ArgumentList "/Online", "/Cleanup-Image", "/RestoreHealth" -NoNewWindow -Wait -PassThru
Add-Content -Path $logFile -Value "DISM Exit Code: $($dismResult.ExitCode)"

# Wait and log time after DISM
$timeAfterDISM = Get-Date
Add-Content -Path $logFile -Value "DISM completed at: $timeAfterDISM"

# Run SFC (System File Checker) scan
Write-Host "Running SFC (System File Checker)..."
Add-Content -Path $logFile -Value "Running SFC command: sfc /scannow"
$sfcResult = Start-Process -FilePath "sfc" -ArgumentList "/scannow" -NoNewWindow -Wait -PassThru
Add-Content -Path $logFile -Value "SFC Exit Code: $($sfcResult.ExitCode)"

# Wait and log time after SFC
$timeAfterSFC = Get-Date
Add-Content -Path $logFile -Value "SFC completed at: $timeAfterSFC"

# Log the total time taken
$endTime = Get-Date
$timeTaken = $endTime - $startTime
Add-Content -Path $logFile -Value "Total Repair Time: $timeTaken"
Add-Content -Path $logFile -Value "========================="
Write-Host "System repair completed. Check the log for details."
