<#
.SYNOPSIS
    MSI Software Installation with Pre-check (System Wide\All Users)
    OS Support: Windows 7 and above
    Required modules: NONE
.DESCRIPTION
    This script checks if the required MSI file exists in the specified directory. If the file is missing, it attempts to copy the file 
    from the worklet payload. Once the file is available, the script installs the MSI silently, logs the installation process, and validates 
    the installation by checking the system registry.
.NOTES
    Modified Date: January 7, 2025
#>

######## EDIT WITHIN THIS BLOCK #######
$fileName = 'vpn.msi'
$custArgs = ''  # Custom arguments for MSI installation
#######################################

############### MAIN CODE #############

# Define paths
$filepath = "$env:TEMP"  # Destination directory for the MSI
$fileFullPath = Join-Path -Path $filepath -ChildPath $fileName
$logPath = Join-Path -Path $filepath -ChildPath "$fileName.log"

# Check if the MSI file exists
if (!(Test-Path -Path $fileFullPath)) {
    Write-Output "MSI file $fileName does not exist in $filepath."
    Write-Output "Attempting to copy the file from the worklet payload..."

    try {
        Copy-Item -Path (Join-Path -Path $PWD -ChildPath $fileName) -Destination $fileFullPath -Force
        Write-Output "File $fileName successfully copied to $fileFullPath."
    } catch {
        Write-Output "Failed to copy $fileName. Exiting."
        Exit 1
    }
} else {
    Write-Output "MSI file $fileName already exists at $fileFullPath."
}

# Construct the MSI installation arguments
if ($custArgs -ne '') {
    $arglist = "/i `"$fileFullPath`" /qn /norestart $custArgs /l*v `"$logPath`""
} else {
    $arglist = "/i `"$fileFullPath`" /qn /norestart /l*v `"$logPath`""
}

Write-Output "Starting MSI installation with the following arguments:"
Write-Output $arglist

# Perform MSI installation
try {
    Start-Process -FilePath "msiexec.exe" -ArgumentList $arglist -Wait -NoNewWindow
} catch {
    Write-Output "MSI installation failed. Check the log file at $logPath for details."
    Exit 1603
}

# Function to retrieve MSI properties
function Get-MSIPropertyList {
    param($FilePath)

    $installer = New-Object -ComObject WindowsInstaller.Installer
    $msiDatabase = $installer.GetType().InvokeMember("OpenDatabase", "InvokeMethod", $null, $installer, @($FilePath, 0))
    $properties = @("ProductCode", "ProductLanguage", "Manufacturer", "ProductVersion", "ProductName")
    $msiProperties = [ordered]@{}

    foreach ($property in $properties) {
        $query = "SELECT Value FROM Property WHERE Property = '$property'"
        $view = $msiDatabase.GetType().InvokeMember("OpenView", "InvokeMethod", $null, $msiDatabase, ($query))
        $view.GetType().InvokeMember("Execute", "InvokeMethod", $null, $view, $null)
        $record = $view.GetType().InvokeMember("Fetch", "InvokeMethod", $null, $view, $null)
        $value = $record.GetType().InvokeMember("StringData", "GetProperty", $null, $record, 1)
        $msiProperties.Add($property, $value)
    }

    $view.GetType().InvokeMember("Close", "InvokeMethod", $null, $view, $null)
    $msiDatabase = $null

    return [PSCustomObject]$msiProperties
}

# Retrieve MSI properties and validate installation
$prop = Get-MSIPropertyList -FilePath $fileFullPath
$guid = $prop.ProductCode
$uninstallPath = "Software\Microsoft\Windows\CurrentVersion\Uninstall"

# Check 64-bit registry
$hklm64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry64)
$skey64 = $hklm64.OpenSubKey("$uninstallPath\$guid")

# Check 32-bit registry
$hklm32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::Registry32)
$skey32 = $hklm32.OpenSubKey("$uninstallPath\$guid")

if ($skey64 -or $skey32) {
    $installedVersion = if ($skey64) {
        [Version]$skey64.GetValue('DisplayVersion')
    } else {
        [Version]$skey32.GetValue('DisplayVersion')
    }

    if ($installedVersion -ge [Version]$prop.ProductVersion) {
        Write-Output "Installation of $fileName successful. Installed version: $installedVersion."
        Exit 0
    }
}

Write-Output "Installation validation failed. Check the log file at $logPath for details."
Exit 1603