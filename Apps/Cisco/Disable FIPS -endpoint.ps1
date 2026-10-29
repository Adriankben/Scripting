#Requires -RunAsAdministrator
# Disable Cisco AnyConnect / Secure Client FIPS
# Run as Administrator

$paths = @(
    "$env:ProgramData\Cisco\Cisco AnyConnect Secure Mobility Client\AnyConnectLocalPolicy.xml",
    "$env:ProgramData\Cisco\Cisco Secure Client\AnyConnectLocalPolicy.xml"
)

$found = $false

foreach ($path in $paths) {
    if (Test-Path $path) {
        $found = $true

        try {
            # Load XML
            [xml]$xml = Get-Content -LiteralPath $path -Raw

            # Find FIPS setting
            $node = $xml.SelectSingleNode("//*[local-name()='FipsMode']")

            if ($null -eq $node) {
                Write-Warning "FipsMode not found in $path"
                continue
            }

            if ($node.InnerText -ceq "false") {
                Write-Host "FIPS already disabled: $path"
                continue
            }

            # Backup configuration
            $backup = "$path.bak.$(Get-Date -Format 'yyyyMMddHHmmss')"
            Copy-Item -LiteralPath $path -Destination $backup -ErrorAction Stop

            # Disable FIPS
            $node.InnerText = "false"
            $xml.Save($path)

            # Verify
            [xml]$verify = Get-Content -LiteralPath $path -Raw
            $result = $verify.SelectSingleNode("//*[local-name()='FipsMode']")

            if ($result.InnerText -ceq "false") {
                Write-Host "SUCCESS: FIPS disabled in $path" -ForegroundColor Green
                Write-Host "Backup: $backup"
                Write-Host "REBOOT REQUIRED to apply change." -ForegroundColor Yellow
            }
            else {
                Write-Warning "Verification failed: $path"
            }
        }
        catch {
            Write-Error "Failed to update ${path}: $_"
        }
    }
}

if (-not $found) {
    Write-Warning "Cisco AnyConnect local policy file not found."
}

# Disable Windows FIPS algorithm policy
# ("System cryptography: Use FIPS compliant algorithms...")
# A RESTART IS REQUIRED for this change to take effect.
# Note: if this policy is enforced by Group Policy, the GPO will
# re-apply it at the next refresh and override this setting.
$fipsKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy"

try {
    if (-not (Test-Path -LiteralPath $fipsKey)) {
        Write-Warning "Windows FIPS policy key not found: $fipsKey"
    }
    else {
        Set-ItemProperty `
            -LiteralPath $fipsKey `
            -Name Enabled `
            -Value 0 `
            -Type DWord `
            -ErrorAction Stop

        # Confirm (expected: 0)
        $current = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa\FipsAlgorithmPolicy" -ErrorAction Stop).Enabled
        Write-Host "FipsAlgorithmPolicy Enabled = $current"

        if ($current -eq 0) {
            Write-Host "SUCCESS: Windows FIPS algorithm policy disabled." -ForegroundColor Green
            Write-Host "RESTART REQUIRED to apply change." -ForegroundColor Yellow
        }
        else {
            Write-Warning "Verification failed: Windows FIPS policy Enabled = $current"
        }
    }
}
catch {
    Write-Error "Failed to disable Windows FIPS policy: $_"
}
