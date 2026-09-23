$Path = "C:\ProgramData\Cisco\Cisco Secure Client\AnyConnectLocalPolicy.xml"

if (-not (Test-Path $Path)) {
    Write-Error "File not found: $Path"
    exit 1
}

# Backup the existing policy
Copy-Item $Path "$Path.bak" -Force

# Load XML
[xml]$Xml = Get-Content $Path -Raw

# Set FIPS mode
if ($Xml.AnyConnectLocalPolicy.FipsMode) {
    $Xml.AnyConnectLocalPolicy.FipsMode = "true"
}
else {
    $Node = $Xml.CreateElement("FipsMode")
    $Node.InnerText = "true"
    $Xml.AnyConnectLocalPolicy.AppendChild($Node) | Out-Null
}

# Save changes
$Xml.Save($Path)

Write-Host "Cisco Secure Client FIPS mode has been set to TRUE." -ForegroundColor Green
Write-Host "Reboot Windows for the change to take effect." -ForegroundColor Yellow


Select-String `
    -Path "C:\ProgramData\Cisco\Cisco Secure Client\AnyConnectLocalPolicy.xml" `
    -Pattern "FipsMode"