#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    This worklet mitigates vulnerabilities by disabling weak ciphers.

.DESCRIPTION
    The script disables weak ciphers to enhance system security in two layers:

    1. Schannel cipher registry keys (Enabled = 0):
        - Triple DES 168 (Sweet32 vulnerability mitigation)
        - DES 56/56
        - RC4 variants
        - RC2 variants

    2. TLS cipher suite list:
        - Removes every enabled DES / 3DES / RC4 / RC2 / NULL suite with Disable-TlsCipherSuite,
          for scanners that check the suite list rather than the registry.

    It also warns when a Group Policy "SSL Cipher Suite Order" is set, because that policy
    overrides the local cipher suite list.

    Each setting is evaluated and only remediated when it is non-compliant.

.NOTES
    All parameters are predefined.
    A device restart is required after any change.

    Exit codes:
        0 - Compliant (no change needed, or changes applied; see output for reboot notice)
        1 - Error reading the registry
        2 - Error remediating the registry
        3 - Error disabling a TLS cipher suite

.LINK
    https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-2183

.LINK
    https://learn.microsoft.com/en-us/powershell/module/tls/disable-tlsciphersuite
#>

Set-StrictMode -Version Latest

###################################################
# PREDEFINED DESIRED REGISTRY CONFIGURATIONS

$cipherRoot = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers'

$weakCiphers = @(
    'Triple DES 168',
    'Triple DES 168/168',
    'DES 56/56',
    'RC2 40/128',
    'RC2 56/128',
    'RC2 128/128',
    'RC4 40/128',
    'RC4 56/128',
    'RC4 64/128',
    'RC4 128/128'
)

$registryInputs = foreach ( $cipher in $weakCiphers ) {
    @{
        Path      = "$cipherRoot\$cipher"
        Name      = 'Enabled'
        Value     = 0
        ValueType = 'DWord'
    }
}

# TLS cipher suite names matching this pattern are removed from the suite list
$weakSuitePattern = '3DES|_DES_|_RC4_|_RC2_|_NULL_'

# GPO-managed cipher suite order (overrides the local list when present)
$gpoSuiteOrderPath = 'SOFTWARE\Policies\Microsoft\Cryptography\Configuration\SSL\00010002'

###################################################
# DEFINE VERBOSITY PREFERENCE

# Uncommenting $VerbosePreference will show additional output in your Activity Log.
# This can be used for troubleshooting purposes.
# $VerbosePreference = 'Continue'

###################################################

# Always use the native registry view so a 32-bit host on a 64-bit OS writes the real keys
$View = if ( [ System.Environment ]::Is64BitOperatingSystem ) { 'Registry64' } else { 'Registry32' }

function Get-LocalMachineKey {
    [ Microsoft.Win32.RegistryKey ]::OpenBaseKey(
        [ Microsoft.Win32.RegistryHive ]::LocalMachine,
        [ Microsoft.Win32.RegistryView ]::$View
    )
}

# Defining testRegistry function
function testRegistry {
    [ OutputType ( [ bool ] ) ]
    param (
        [ Parameter ( Position = 0, Mandatory = $true ) ]
        [ ValidateNotNullOrEmpty () ]
        [ String ] $Path,

        [ Parameter ( Position = 1, Mandatory = $true ) ]
        [ ValidateNotNullOrEmpty () ]
        [ String ] $Name,

        [ Parameter ( Position = 2, Mandatory = $true ) ]
        [ Int32 ] $Value,

        [ Parameter ( Position = 3, Mandatory = $true ) ]
        [ ValidateSet ( 'DWord' ) ]
        [ String ] $ValueType
    )

    $baseKey = $null
    $subKey = $null
    try {
        $baseKey = Get-LocalMachineKey
        $subKey = $baseKey.OpenSubKey( $Path )

        if ( -not $subKey ) {
            Write-Verbose "$Path does not exist."
            return $false
        }

        if ( $Name -notin $subKey.GetValueNames() ) {
            Write-Verbose "$Name was not found under $Path."
            return $false
        }

        if ( $subKey.GetValueKind( $Name ).ToString() -ne $ValueType ) {
            Write-Verbose "$Name type does not match the expected type of $ValueType."
            return $false
        }

        if ( [ Int32 ] $subKey.GetValue( $Name ) -ne $Value ) {
            Write-Verbose "$Name value does not match the expected value of $Value."
            return $false
        }

        return $true
    } catch {
        Write-Error "An error occurred while accessing the registry: $( $_.Exception.Message )"
        exit 1
    } finally {
        if ( $subKey ) { $subKey.Dispose() }
        if ( $baseKey ) { $baseKey.Dispose() }
    }
}

# Defining setRegistry Function
function setRegistry {
    param (
        [ Parameter ( Position = 0, Mandatory = $true ) ]
        [ ValidateNotNullOrEmpty () ]
        [ String ] $Path,

        [ Parameter ( Position = 1, Mandatory = $true ) ]
        [ ValidateNotNullOrEmpty () ]
        [ String ] $Name,

        [ Parameter ( Position = 2, Mandatory = $true ) ]
        [ Int32 ] $Value,

        [ Parameter ( Position = 3, Mandatory = $true ) ]
        [ ValidateSet ( 'DWord' ) ]
        [ String ] $ValueType
    )

    $baseKey = $null
    $subKey = $null
    try {
        $baseKey = Get-LocalMachineKey
        # CreateSubKey handles the '/' in names such as 'DES 56/56', which New-Item cannot
        $subKey = $baseKey.CreateSubKey( $Path )
        $subKey.SetValue( $Name, $Value, [ Microsoft.Win32.RegistryValueKind ]::$ValueType )
        Write-Output "Set $Path\$Name = $Value."
    } catch {
        Write-Error "An error occurred while remediating the registry: $( $_.Exception.Message )"
        exit 2
    } finally {
        if ( $subKey ) { $subKey.Dispose() }
        if ( $baseKey ) { $baseKey.Dispose() }
    }
}

$changesMade = $false

###################################################
# 1. SCHANNEL CIPHER REGISTRY KEYS

$remediationInputs = @(
    foreach ( $cfg in $registryInputs ) {
        if ( -not ( testRegistry @cfg ) ) { $cfg }
    }
)

if ( $remediationInputs.Count -gt 0 ) {
    Write-Verbose 'Running setRegistry function.'
    foreach ( $cfg in $remediationInputs ) { setRegistry @cfg }
    $changesMade = $true
} else {
    Write-Output 'Schannel cipher registry keys are already compliant.'
}

###################################################
# 2. TLS CIPHER SUITE LIST

if ( Get-Command -Name Disable-TlsCipherSuite -ErrorAction SilentlyContinue ) {
    $weakSuites = @( Get-TlsCipherSuite | Where-Object { $_.Name -match $weakSuitePattern } )

    if ( $weakSuites.Count -gt 0 ) {
        foreach ( $suite in $weakSuites ) {
            try {
                Disable-TlsCipherSuite -Name $suite.Name -ErrorAction Stop
                Write-Output "Disabled TLS cipher suite: $( $suite.Name )."
            } catch {
                Write-Error "Failed to disable TLS cipher suite $( $suite.Name ): $( $_.Exception.Message )"
                exit 3
            }
        }
        $changesMade = $true
    } else {
        Write-Output 'No weak TLS cipher suites are enabled.'
    }
} else {
    Write-Warning 'The TLS module is not available on this OS. The Schannel registry keys alone still block these ciphers.'
}

###################################################
# 3. GROUP POLICY OVERRIDE CHECK

$gpoBase = $null
$gpoKey = $null
try {
    $gpoBase = Get-LocalMachineKey
    $gpoKey = $gpoBase.OpenSubKey( $gpoSuiteOrderPath )
    if ( $gpoKey -and ( 'Functions' -in $gpoKey.GetValueNames() ) ) {
        $gpoSuites = [ String ] $gpoKey.GetValue( 'Functions' )
        if ( $gpoSuites -match $weakSuitePattern ) {
            Write-Warning 'GPO "SSL Cipher Suite Order" includes weak suites and overrides local settings. Remove them from the policy.'
        } else {
            Write-Verbose 'GPO "SSL Cipher Suite Order" is set and contains no weak suites.'
        }
    }
} catch {
    Write-Warning "Could not read the GPO cipher suite order: $( $_.Exception.Message )"
} finally {
    if ( $gpoKey ) { $gpoKey.Dispose() }
    if ( $gpoBase ) { $gpoBase.Dispose() }
}

###################################################
# RESULT

if ( $changesMade ) {
    Write-Output 'Weak ciphers have been disabled. Restart the device to complete remediation.'
} else {
    Write-Output 'All specified ciphers are already disabled. Device is compliant.'
}
exit 0
