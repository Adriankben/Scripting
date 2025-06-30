# Import Excel data
$ExcelPath = "C:\Users\it-abennett\Documents\LGS Distribution Groups.xlsx"
$LogPath = "C:\AD_DistributionGroupMigration_Log.txt"
Import-Module ActiveDirectory

# Clear old log
Remove-Item -Path $LogPath -ErrorAction SilentlyContinue

# Import Excel data
$data = Import-Excel -Path $ExcelPath

# Set OUs
$TargetGroupOU = "OU=NAMING-LG,OU=Distribution Groups,OU=Company,DC=company,DC=com"
$UserSearchBase = "OU=NAMING-LG,OU=User Accounts,OU=Company,DC=company,DC=com"

# Get unique group names
$uniqueGroups = $data | Select-Object -ExpandProperty GroupName -Unique

foreach ($groupName in $uniqueGroups) {
    # Check if the distribution group exists
    $group = Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $TargetGroupOU -ErrorAction SilentlyContinue

    if (-not $group) {
        try {
            $group = New-ADGroup -Name $groupName -Path $TargetGroupOU -GroupScope Universal -GroupCategory Distribution
            Add-Content $LogPath "Created distribution group: $groupName"
        } catch {
            Add-Content $LogPath "ERROR creating group ${groupName}: $_"
            continue
        }
    }

    # Add members from Excel
    $groupMembers = $data | Where-Object { $_.GroupName -eq $groupName }

    foreach ($row in $groupMembers) {
        $displayName = $row.MemberName

        # Try to match user by DisplayName in the specified OU
        $user = Get-ADUser -Filter "DisplayName -like '*$displayName*'" -SearchBase $UserSearchBase -Properties DisplayName, SamAccountName -ErrorAction SilentlyContinue

        if ($user) {
            $samAccountName = $user.SamAccountName
            try {
                Add-ADGroupMember -Identity $groupName -Members $samAccountName -ErrorAction Stop
                Add-Content $LogPath "Added user [$displayName] (SamAccountName: $samAccountName) to group $groupName"
            } catch {
                Add-Content $LogPath "ERROR adding [$displayName] (SamAccountName: $samAccountName) to ${groupName}: $_"
            }
        } else {
            Add-Content $LogPath "WARNING: User [$displayName] not found in MIA-LG user OU"
        }
    }
}
