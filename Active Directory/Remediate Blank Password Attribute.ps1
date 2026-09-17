$SamAccountName = 'TargetName'

Import-Module ActiveDirectory

try {
    $User = Get-ADUser -Identity $SamAccountName `
        -Properties PasswordNotRequired `
        -ErrorAction Stop

    if ($User.PasswordNotRequired) {

        Set-ADUser -Identity $User `
            -PasswordNotRequired $false `
            -ErrorAction Stop

        Write-Host "Remediated: $SamAccountName - PasswordNotRequired is now False."
    }
    else {
        Write-Host "No change required: $SamAccountName already requires a password."
    }
}
catch {
    Write-Error "Unable to process $SamAccountName : $($_.Exception.Message)"
}