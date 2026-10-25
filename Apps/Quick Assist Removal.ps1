$pkg = Get-AppxPackage -AllUsers -Name MicrosoftCorporationII.QuickAssist -ErrorAction SilentlyContinue

if ($pkg) {
    $pkg | Remove-AppxPackage -AllUsers -ErrorAction SilentlyContinue
    Write-Host "Quick Assist removal attempted."
} else {
    Write-Host "Quick Assist package not found for installed users."
}

$prov = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*QuickAssist*"}
if ($prov) {
    $prov | Remove-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Out-Null
    Write-Host "Provisioned Quick Assist package removal attempted."
} else {
    Write-Host "No provisioned Quick Assist package found."
}

$check1 = Get-AppxPackage -AllUsers -Name MicrosoftCorporationII.QuickAssist -ErrorAction SilentlyContinue
$check2 = Get-AppxProvisionedPackage -Online | Where-Object {$_.DisplayName -like "*QuickAssist*"}

if (-not $check1 -and -not $check2) {
    Write-Host "Success: Quick Assist is no longer installed or provisioned."
} else {
    Write-Host "Quick Assist still appears present. Review package state manually."
}