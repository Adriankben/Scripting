# Define the PAC script URL
$pacUrl = "http://proxyserver/proxy.pac"

# Enable Proxy Auto Config script
$registryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
Set-ItemProperty -Path $registryPath -Name "AutoConfigURL" -Value $pacUrl

# Notify the system about the changes
$refresh = New-Object -ComObject Shell.Application
$refresh.Windows()

Write-Output "Proxy setup script enabled: $pacUrl"


Get-ChildItem "C:\Users" -Force | ForEach-Object {
    $userRegPath = "C:\Users\$_\NTUSER.DAT"
    if (Test-Path $userRegPath) {
        reg load HKU\TempUser $userRegPath
        Set-ItemProperty -Path "HKU:\TempUser\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name AutoConfigURL -Value $pacUrl
        reg unload HKU\TempUser
    }
}





