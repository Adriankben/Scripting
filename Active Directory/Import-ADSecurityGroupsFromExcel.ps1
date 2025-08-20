# Import Excel data
$ExcelPath = "C:\Users\it-abennett\Documents\SecurityGroupsExport.xlsx"
$LogPath = "C:\AD_GroupMigration_Log.txt"
Import-Module ActiveDirectory

# Clear old log
Remove-Item -Path $LogPath -ErrorAction SilentlyContinue

# Import Excel data
$data = Import-Excel -Path $ExcelPath

# Set OUs
$TargetGroupOU = "OU=NAMING,OU=Groups,OU=Company,DC=company,DC=com"
$UserSearchBase = "OU=NAMING,OU=User Accounts,OU=Company,DC=company,DC=com"

foreach ($row in $data) {
    $groupName = $row.GroupName
    $displayName = $row.MemberName

    # Check if group exists
    if (-not (Get-ADGroup -Filter "Name -eq '$groupName'" -SearchBase $TargetGroupOU -ErrorAction SilentlyContinue)) {
        try {
            New-ADGroup -Name $groupName -Path $TargetGroupOU -GroupScope Global -GroupCategory Security
            Add-Content $LogPath "Created group: $groupName"
        } catch {
            Add-Content $LogPath "ERROR creating group ${groupName}: $_"
            continue
        }
    }

    # Try to match user by DisplayName scoped to the correct OU
    $user = Get-ADUser -Filter "DisplayName -like '*$displayName*'" -SearchBase $UserSearchBase -Properties DisplayName, SamAccountName -ErrorAction SilentlyContinue

    if ($user) {
        $samAccountName = $user.SamAccountName

        try {
            Add-ADGroupMember -Identity $groupName -Members $samAccountName
            Add-Content $LogPath "Added user [$displayName] (SamAccountName: $samAccountName) to group $groupName"
        } catch {
            Add-Content $LogPath "ERROR adding [$displayName] (SamAccountName: $samAccountName) to ${groupName}: $_"
        }
    } else {
        Add-Content $LogPath "WARNING: User [$displayName] not found in MIA-LG user OU"
    }
}
