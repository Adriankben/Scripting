<#
.SYNOPSIS
    Example: Audit and report on specific distribution groups and mailboxes in Exchange Online.
.DESCRIPTION
    - Connects to Exchange Online
    - Finds distribution groups matching a keyword
    - Lists members of those groups
    - Counts total user mailboxes
    - Disconnects from session
#>

# Connect to Exchange Online
Connect-ExchangeOnline -UserPrincipalName your-admin@domain.com

# Find distribution groups containing a specific keyword
$keyword = "example"  # Replace with your keyword
$groups = Get-DistributionGroup | Where-Object { $_.DisplayName -match $keyword }
Write-Host "`n Found $($groups.Count) distribution groups matching '$keyword'"

# Count total user mailboxes
$mailboxes = Get-Mailbox -RecipientTypeDetails UserMailbox
Write-Host " Total user mailboxes: $($mailboxes.Count)"

# List members of each matching group
Write-Host "`n Listing group members..." -ForegroundColor Cyan

foreach ($group in $groups) {
    Write-Host "`n Group: $($group.DisplayName) ($($group.PrimarySmtpAddress))" -ForegroundColor Yellow

    try {
        $members = Get-DistributionGroupMember -Identity $group.Identity | Select-Object Name, PrimarySMTPAddress
        if ($members) {
            $members | Format-Table Name, PrimarySMTPAddress -AutoSize
        } else {
            Write-Host "    No members found." -ForegroundColor DarkGray
        }
    } catch {
        Write-Warning "    Error retrieving members for $($group.DisplayName): $_"
    }

    Write-Host "----------------------------------------"
}

# Disconnect from Exchange Online
Disconnect-ExchangeOnline -Confirm:$false
Write-Host "`n Done." -ForegroundColor Green
