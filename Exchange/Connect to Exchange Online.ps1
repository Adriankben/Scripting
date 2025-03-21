# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName it-abennett@gatelesis.com

# Get all distribution groups containing "mro"
$mroGroups = Get-DistributionGroup | Where-Object { $_.DisplayName -match "mro" }
$mroGroupCount = $mroGroups.Count
Write-Host " Total MRO Distribution Groups: $mroGroupCount"

# Get total number of mailboxes
$mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox
$mailboxCount = $mailboxes.Count
Write-Host " Total Mailboxes in Use: $mailboxCount"

# Get distribution group members (recipients of emails)
Write-Host "`n Listing MRO Distribution Groups and their Recipients..." -ForegroundColor Cyan
foreach ($group in $mroGroups) {
    Write-Host " Group: $($group.DisplayName) ($($group.PrimarySmtpAddress))" -ForegroundColor Yellow
    $members = Get-DistributionGroupMember -Identity $group.Identity | Select-Object Name, PrimarySMTPAddress
    if ($members) {
        $members | Format-Table Name, PrimarySMTPAddress -AutoSize
    } else {
        Write-Host "    No members found in this group." -ForegroundColor Red
    }
    Write-Host "----------------------------------------"
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false

Write-Host "`n Script Execution Complete!" -ForegroundColor Green
