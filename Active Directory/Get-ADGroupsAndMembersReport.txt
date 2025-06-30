<#
    This script retrieves all groups (including distribution groups) within a specified 
    Active Directory OU. For each group, it collects the group’s name, email address, 
    and recursively enumerates all user members. It outputs a CSV report listing each 
    group alongside its members’ SamAccountNames. Groups without members are included 
    with a placeholder entry "(No Members)". The report is saved to a specified file path.
#>

# Define the distinguished name (DN) of the OU to search groups in
$OU = "OU=Example LLC,DC=Company,DC=com"

# Define output CSV path
$outputPath = "C:\AD_Group_Members_With_Emails.csv"

# Get all groups in the specified OU, including their 'mail' property
$Groups = Get-ADGroup -Filter * -SearchBase $OU -Properties mail

# Use a list for better performance when accumulating results
$Output = New-Object System.Collections.Generic.List[PSObject]

foreach ($Group in $Groups) {
    $GroupEmail = if ($Group.mail) { $Group.mail } else { "" }
    $GroupName = $Group.Name

    try {
        # Get members recursively, filter only users
        $Members = Get-ADGroupMember -Identity $Group.DistinguishedName -Recursive -ErrorAction Stop |
                   Where-Object { $_.objectClass -eq 'user' }
    } catch {
        Write-Warning "Failed to get members of group '$GroupName': $_"
        $Members = @()
    }

    if ($Members.Count -gt 0) {
        foreach ($Member in $Members) {
            $Output.Add([PSCustomObject]@{
                GroupName  = $GroupName
                GroupEmail = $GroupEmail
                MemberName = $Member.SamAccountName
            })
        }
    }
    else {
        # Add a placeholder when no user members found
        $Output.Add([PSCustomObject]@{
            GroupName  = $GroupName
            GroupEmail = $GroupEmail
            MemberName = "(No Members)"
        })
    }
}

# Export all results to CSV
$Output | Export-Csv -Path $outputPath -NoTypeInformation -Encoding UTF8

Write-Output "Report saved to $outputPath"
