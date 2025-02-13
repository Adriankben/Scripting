# Check the current SMB settings
$smbConfig = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol

Write-Host "Current SMB Configuration:"
Write-Host "SMBv1 Enabled: $($smbConfig.EnableSMB1Protocol)"
Write-Host "SMBv2 Enabled: $($smbConfig.EnableSMB2Protocol)"

# Enable SMBv2 first if it's disabled
if (-not $smbConfig.EnableSMB2Protocol) {
    Write-Host "Enabling SMBv2..."
    Set-SmbServerConfiguration -EnableSMB2Protocol $true -Force
    Start-Sleep -Seconds 5  # Wait to ensure changes take effect
}

# Re-check SMB settings after enabling SMBv2
$smbConfig = Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol

# Disable SMBv1 only if SMBv2 is successfully enabled
if ($smbConfig.EnableSMB2Protocol -and $smbConfig.EnableSMB1Protocol) {
    Write-Host "Disabling SMBv1..."
    Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force
}

Write-Host "Final SMB Configuration:"
Get-SmbServerConfiguration | Select-Object EnableSMB1Protocol, EnableSMB2Protocol

Write-Host "SMB settings updated. A restart may be required for changes to take effect."
