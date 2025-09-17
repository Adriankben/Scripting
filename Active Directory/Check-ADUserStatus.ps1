$users = @("abennett@domain.com", "kbennett@domain.com")
$logFile = "C:\Logs\UserStatusLog.txt"  # Update this path as needed

# Ensure the log directory exists
$logDir = Split-Path $logFile
if (-not (Test-Path $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force
}

# Optionally clear the log before running
Clear-Content -Path $logFile -ErrorAction SilentlyContinue

foreach ($user in $users) {
    try {
        $adUser = Get-ADUser -LDAPFilter "(mail=$user)" -Properties Enabled

        if (!$adUser) {
            $message = "$user: Not Found"
        } elseif ($adUser.Enabled -eq $false) {
            $message = "$user: Disabled"
        } else {
            $message = "$user: Active"
        }
    } catch {
        $message = "$user: Error - $_"
    }

    # Log to file and optionally to console
    $timestampedMessage = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message"
    Add-Content -Path $logFile -Value $timestampedMessage
    Write-Host $message
}
