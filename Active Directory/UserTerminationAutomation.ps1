<#
.SYNOPSIS
    Search for an AD user by display name, select a user, remove them from all groups except "Domain Users",
    disable the user account, and update the description to "Term".

.DESCRIPTION
    The script prompts for a display name, lists matching users for selection, then processes the selected user:
    - Lists group memberships excluding "Domain Users"
    - Asks for confirmation before removal from groups
    - Disables the user account
    - Sets the description to "Term"
#>

# Ensure Active Directory module is imported
Import-Module ActiveDirectory -ErrorAction Stop

# Prompt for user display name to search
$displayName = Read-Host "Enter the display name of the user"

# Search AD for users matching display name (wildcard), get relevant properties
$matchedUsers = @(Get-ADUser -Filter "DisplayName -like '*$displayName*'" -Properties DisplayName, EmailAddress, SamAccountName)

if ($matchedUsers.Count -eq 0) {
    Write-Warning "No users found matching '$displayName'. Exiting script."
    exit
}

# Display matching users with index for selection
Write-Host "Matching users:"
for ($i = 0; $i -lt $matchedUsers.Count; $i++) {
    $user = $matchedUsers[$i]
    Write-Host "[$i] Display Name: $($user.DisplayName), Email: $($user.EmailAddress)"
}

# Prompt user to select from the list by index
$userIndexInput = Read-Host "Enter the number of the user you want to select"

# Validate input
if (-not [int]::TryParse($userIndexInput, [ref]$null) -or $userIndexInput -lt 0 -or $userIndexInput -ge $matchedUsers.Count) {
    Write-Warning "Invalid selection. Exiting script."
    exit
}

$selectedUser = $matchedUsers[$userIndexInput]
Write-Host "Selected User: $($selectedUser.DisplayName) <$($selectedUser.EmailAddress)>"

# Retrieve group memberships of the selected user
$groupDNs = Get-ADUser -Identity $selectedUser.SamAccountName -Properties MemberOf | Select-Object -ExpandProperty MemberOf

if (-not $groupDNs) {
    Write-Host "User is not a member of any groups."
    $groupsToRemove = @()
} else {
    # Retrieve group objects, exclude 'Domain Users'
    $groupsToRemove = foreach ($dn in $groupDNs) {
        $group = Get-ADGroup -Identity $dn -ErrorAction SilentlyContinue
        if ($group -and $group.Name -ne "Domain Users") {
            $group
        }
    }
}

if ($groupsToRemove.Count -eq 0) {
    Write-Host "User is only a member of 'Domain Users' or no removable groups found. No group removal needed."
} else {
    Write-Host "`nUser will be removed from the following groups:"
    $groupsToRemove | ForEach-Object { Write-Host "- $($_.Name)" }

    # Confirm before proceeding
    $confirmation = Read-Host "`nProceed with removal from these groups? (Y/N)"
    if ($confirmation -notmatch '^[Yy]$') {
        Write-Host "Operation cancelled by user."
        exit
    }

    # Remove user from groups, with error handling
    foreach ($group in $groupsToRemove) {
        try {
            Remove-ADGroupMember -Identity $group -Members $selectedUser -Confirm:$false -ErrorAction Stop
            Write-Host "Removed from group: $($group.Name)"
        }
        catch {
            Write-Warning "Failed to remove user from group $($group.Name): $_"
        }
    }
}

# Disable the user account and set description to "Term" with today's date in MM/dd/yyyy format
try {
    # Get today's date in "MM/dd/yyyy" format
    $dateToday = Get-Date -Format "MM/dd/yyyy"
    
    # Disable the user account
    Disable-ADAccount -Identity $selectedUser -ErrorAction Stop
    
    # Set the user description to "Term" with the current date
    Set-ADUser -Identity $selectedUser -Description "Term - $dateToday" -ErrorAction Stop
    
    Write-Host "User account disabled and description set to 'Term - $dateToday'." -ForegroundColor Green
}
catch {
    Write-Warning "Failed to disable user or set description: $_"
}
