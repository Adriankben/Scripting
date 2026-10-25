<#
.SYNOPSIS
    Finds and displays the primary Active Directory group for a given object.
.DESCRIPTION
    This function retrieves the PrimaryGroupID for a user or computer object and resolves it to the actual group name
    by constructing the full SID using the domain SID.
.EXAMPLE
    Get-PrimaryGroup -ObjectName "it-jchery"
#>

function Get-PrimaryGroup {
    param (
        [Parameter(Mandatory = $true)]
        [string]$ObjectName
    )

    try {
        # Get the AD object (user, computer, etc.) with its PrimaryGroupID
        $object = Get-ADObject -Filter { Name -eq $ObjectName } -Properties PrimaryGroupID

        if (-not $object) {
            Write-Host "Object '$ObjectName' not found in Active Directory." -ForegroundColor Red
            return
        }

        $primaryGroupID = $object.PrimaryGroupID
        $domainSID = (Get-ADDomain).DomainSID
        $primaryGroupSID = "$domainSID-$primaryGroupID"

        # Find the group using the constructed SID
        $primaryGroup = Get-ADGroup -Filter "objectSID -eq '$primaryGroupSID'" -ErrorAction Stop

        if ($primaryGroup) {
            Write-Host "Primary group of '$ObjectName': $($primaryGroup.Name)" -ForegroundColor Green
        } else {
            Write-Host "Primary group for '$ObjectName' could not be found using SID '$primaryGroupSID'." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Error occurred: $($_.Exception.Message)" -ForegroundColor Red
    }
}
