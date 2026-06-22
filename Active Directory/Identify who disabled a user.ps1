$UserToCheck = 'username'   # samAccountName of the account to check
$LookBackDays = 1           # how far back you want to search
$DC = 'DC-1'                 # target domain controller

$start = (Get-Date).AddDays(-$LookBackDays)

Get-WinEvent -ComputerName $DC -FilterHashtable @{
    LogName   = 'Security'
    Id        = 4725
    StartTime = $start
} | ForEach-Object {
    $xml = [xml]$_.ToXml()
    $data = @{}
    foreach ($d in $xml.Event.EventData.Data) { $data[$d.Name] = $d.'#text' }

    if ($data['TargetUserName'] -ieq $UserToCheck) {
        [PSCustomObject]@{
            TimeCreated       = $_.TimeCreated
            DisabledUser      = $data['TargetUserName']
            DisabledBy        = $data['SubjectUserName']
            DisabledByDomain  = $data['SubjectDomainName']
            DisabledBySID     = $data['SubjectUserSid']
            CallerLogonId     = $data['SubjectLogonId']
            DC                = $_.MachineName
        }
    }
} | Sort-Object TimeCreated -Descending | Format-Table -Auto