# Define the SID to search for
$SID = "S-1-5-21-1757981266-162531612-839522115-29954"

# Import the Active Directory module
Import-Module ActiveDirectory

# Try to find the object as a User
$User = Get-ADUser -Filter {SID -eq $SID} -Properties DisplayName, DistinguishedName -ErrorAction SilentlyContinue

# Try to find the object as a Group if not found as a User
if (-not $User) {
    $Group = Get-ADGroup -Filter {SID -eq $SID} -Properties DisplayName, DistinguishedName -ErrorAction SilentlyContinue
}

# Output the found object
if ($User) {
    Write-Output "Found User: $($User.DisplayName)"
    Write-Output "Distinguished Name: $($User.DistinguishedName)"
    $ObjectDN = $User.DistinguishedName
} elseif ($Group) {
    Write-Output "Found Group: $($Group.DisplayName)"
    Write-Output "Distinguished Name: $($Group.DistinguishedName)"
    $ObjectDN = $Group.DistinguishedName
} else {
    Write-Output "No User or Group found for SID: $SID"
    exit
}

# Check delegated permissions on the object
Write-Output "Checking delegated permissions..."
$ACL = Get-Acl "AD:$ObjectDN"

# Parse and output the permissions
$ACL.Access | ForEach-Object {
    [PSCustomObject]@{
        IdentityReference = $_.IdentityReference
        AccessControlType = $_.AccessControlType
        ActiveDirectoryRights = $_.ActiveDirectoryRights
        InheritanceType = $_.InheritanceType
        ObjectType = $_.ObjectType
        InheritedObjectType = $_.InheritedObjectType
    }
}

