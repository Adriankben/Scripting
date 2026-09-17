$AccountName = "LAPSadmin"
$Description = "LAPS-managed local administrator account"

function New-CryptoPassword {
    $Length = 32
    $Chars = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%*-_=+"

    $Bytes = New-Object byte[] ($Length)
    $Rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $Rng.GetBytes($Bytes)
    $Rng.Dispose()

    $Password = -join ($Bytes | ForEach-Object {
        $Chars[$_ % $Chars.Length]
    })

    return $Password
}

$User = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue

if (-not $User) {

    $PlainPassword = New-CryptoPassword

    $SecurePassword = ConvertTo-SecureString `
        $PlainPassword `
        -AsPlainText `
        -Force

    New-LocalUser `
        -Name $AccountName `
        -Password $SecurePassword `
        -Description $Description `
        -AccountNeverExpires `
        -PasswordNeverExpires:$false

    # Immediately remove plaintext variable
    $PlainPassword = $null

    Write-Output "$AccountName created."
}
else {
    if (-not $User.Enabled) {
        Enable-LocalUser -Name $AccountName
        Write-Output "$AccountName enabled."
    }
}

# Ensure it is a member of the local Administrators group
$IsAdmin = Get-LocalGroupMember `
    -Group "Administrators" `
    -ErrorAction SilentlyContinue |
    Where-Object {
        $_.Name -match "\\$([regex]::Escape($AccountName))$"
    }

if (-not $IsAdmin) {

    Add-LocalGroupMember `
        -Group "Administrators" `
        -Member $AccountName

    Write-Output "$AccountName added to local Administrators."
}