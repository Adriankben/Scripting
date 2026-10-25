<# Check Last Reboot Time

Event ID	Meaning
1074	Planned restart/shutdown
6005	Event Log service started
6006	Clean shutdown
6008	Unexpected shutdown
41	Kernel power issue
#>

Get-CimInstance Win32_OperatingSystem |
Select CSName, LastBootUpTime


Get-WinEvent -FilterHashtable @{
    LogName='System'
    Id=1074,6005,6006,6008,41
    StartTime=(Get-Date).AddDays(-2)
} | Select TimeCreated, Id, ProviderName, Message