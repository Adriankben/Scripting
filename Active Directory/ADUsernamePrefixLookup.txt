<#
  This script reads a list of username prefixes (e.g., "jsmith", "ado") from a CSV file, then
  searches Active Directory for any user accounts whose SamAccountName starts with each prefix.
  For each matching user, it collects key details like DisplayName, SamAccountName, and
  DistinguishedName, and outputs this information both to the console and to a CSV file.
  If no matching user is found for a prefix, it records "Not Found" for that entry.
#>

Import-Module ActiveDirectory

$csvPath = "C:\Path\To\initiallastnames.csv"
$outputPath = "C:\Path\To\AD_UserResults.csv"

$usernames = Get-Content $csvPath
$results = @()

foreach ($name in $usernames) {
    $name = $name.Trim()
    $filter = "SamAccountName -like '$name*'"
    $users = Get-ADUser -Filter $filter -Properties DisplayName, SamAccountName, DistinguishedName

    if ($users) {
        foreach ($user in $users) {
            Write-Host "Found: $name"
            Write-Host "  DisplayName: $($user.DisplayName)"
            Write-Host "  SamAccountName: $($user.SamAccountName)"
            Write-Host "  DN: $($user.DistinguishedName)"
            Write-Host "---------------------------"

            $results += [PSCustomObject]@{
                InputName          = $name
                DisplayName        = $user.DisplayName
                SamAccountName     = $user.SamAccountName
                DistinguishedName  = $user.DistinguishedName
            }
        }
    } else {
        Write-Host "Not found: $name"
        Write-Host "---------------------------"

        $results += [PSCustomObject]@{
            InputName          = $name
            DisplayName        = "Not Found"
            SamAccountName     = "Not Found"
            DistinguishedName  = "Not Found"
        }
    }
}

$results | Export-Csv -Path $outputPath -NoTypeInformation
