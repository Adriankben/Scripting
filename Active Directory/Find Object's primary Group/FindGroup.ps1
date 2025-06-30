# Function to find and display the primary group of an AD object
function Get-PrimaryGroup {
    param (
        [string]$ObjectName
    )

    try {
        # Retrieve the object (user or computer) and its PrimaryGroupID
        $object = Get-ADObject -Filter { Name -eq $ObjectName } -Properties PrimaryGroupID
        if (-not $object) {
            Write-Host "Object '$ObjectName' not found in Active Directory." -ForegroundColor Red
            return
        }

        $primaryGroupID = $object.PrimaryGroupID

        # Get the domain's SID
        $domainSID = (Get-ADDomain).DomainSID

        # Construct the primary group SID using the domain SID and PrimaryGroupID
        $primaryGroupSID = "$domainSID-$primaryGroupID"

        # Find the group using the constructed SID
        $primaryGroup = Get-ADGroup -Filter "objectSID -eq '$primaryGroupSID'"

        if ($primaryGroup) {
            Write-Host "Primary group of '$ObjectName': $($primaryGroup.Name)" -ForegroundColor Green
        } else {
            Write-Host "Primary group for '$ObjectName' could not be found." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

# Example usage
# Replace 'UserNameOrComputerName' with the name of the object you want to check
Get-PrimaryGroup -ObjectName "it-jchery"
