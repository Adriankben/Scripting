# Get all Active Directory domain controllers and display their Name, IPv4 address, and Site

Get-ADDomainController -Filter * | Select-Object Name, IPv4Address, Site | 
Export-Csv -Path "DomainControllers.csv" -NoTypeInformation
