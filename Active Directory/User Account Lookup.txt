
Get-ADUser -Filter "Name -like '*John Smith*'" -Properties DisplayName,SamAccountName,EmailAddress,Enabled,LockedOut,LastLogonDate |
Select DisplayName,SamAccountName,EmailAddress,Enabled,LockedOut,LastLogonDate