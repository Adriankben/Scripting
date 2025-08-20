# Stop the Print Spooler service immediately, forcing it to stop if necessary
Stop-Service -Name Spooler -Force

# Disable the Print Spooler service so it does not start automatically on boot
Set-Service -Name Spooler -StartupType Disabled

# Display the current status of the Print Spooler service
Get-Service -Name Spooler
