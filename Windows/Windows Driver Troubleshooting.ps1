<#
.SYNOPSIS
    Windows Driver Troubleshooting Tool
.DESCRIPTION
    This PowerShell script provides helper functions for listing, searching, 
    and removing drivers, including automated cleanup for specific vendors like Logitech.
.NOTES
    Run as Administrator.
#>

function List-Drivers {
    pnputil /enum-drivers
}

function Search-Driver {
    param([string]$Keyword)
    pnputil /enum-drivers | Select-String $Keyword -Context 0,6
}

function Find-DriverBySys {
    param([string]$SysFile)
    driverquery /v /fo list | findstr /i $SysFile
}

function Remove-Driver {
    param([string]$InfName)
    pnputil /delete-driver $InfName /uninstall /force
}

function Remove-DriversByKeyword {
    param([string]$Keyword)
    pnputil /enum-drivers |
        Select-String $Keyword -Context 0,6 |
        ForEach-Object { 
            if ($_ -match "oem\d+\.inf") {
                Write-Host "Removing $($matches[0])..."
                pnputil /delete-driver $matches[0] /uninstall /force
            }
        }
}

function Find-Lvrs64Driver {
    Write-Host "Searching for lvrs64.sys..."
    driverquery /v /fo list | findstr /i lvrs64.sys
    Get-WmiObject Win32_PnPSignedDriver | Where-Object { $_.DriverName -match "lvrs64" } | 
        Select-Object DeviceName, DriverVersion, Manufacturer, InfName
}

Write-Host "Driver Troubleshooting Tool Loaded."
Write-Host "Available commands:"
Write-Host "  List-Drivers"
Write-Host "  Search-Driver -Keyword <string>"
Write-Host "  Find-DriverBySys -SysFile <name>"
Write-Host "  Remove-Driver -InfName <oemXX.inf>"
Write-Host "  Remove-DriversByKeyword -Keyword <string>"
Write-Host "  Find-Lvrs64Driver"
