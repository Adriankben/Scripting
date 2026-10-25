# Enable Windows Prefetch and SysMain
# Windows 11

$PrefetchPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PrefetchParameters"

Write-Host "Enabling Windows Prefetch..." -ForegroundColor Cyan

try {
    # Create PrefetchParameters key if missing
    if (-not (Test-Path $PrefetchPath)) {
        New-Item -Path $PrefetchPath -Force | Out-Null
    }

    # Enable application + boot prefetching
    New-ItemProperty `
        -Path $PrefetchPath `
        -Name "EnablePrefetcher" `
        -PropertyType DWord `
        -Value 3 `
        -Force | Out-Null

    Write-Host "[OK] EnablePrefetcher set to 3"

    # Enable SysMain service
    Set-Service -Name "SysMain" -StartupType Automatic

    # Start SysMain if it isn't already running
    $SysMain = Get-Service -Name "SysMain"

    if ($SysMain.Status -ne "Running") {
        Start-Service -Name "SysMain"
    }

    Write-Host "[OK] SysMain enabled and running"

    # Verify settings
    $PrefetchValue = Get-ItemPropertyValue `
        -Path $PrefetchPath `
        -Name "EnablePrefetcher"

    $SysMain = Get-Service -Name "SysMain"

    Write-Host ""
    Write-Host "Verification:" -ForegroundColor Yellow
    Write-Host "EnablePrefetcher : $PrefetchValue"
    Write-Host "SysMain Status   : $($SysMain.Status)"
    Write-Host "SysMain Startup  : $((Get-CimInstance Win32_Service -Filter "Name='SysMain'").StartMode)"

    Write-Host ""
    Write-Host "Prefetch has been enabled successfully." -ForegroundColor Green
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}