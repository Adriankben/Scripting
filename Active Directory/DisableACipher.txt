<#
.SYNOPSIS
    This worklet mitigates vulnerabilities by disabling weak ciphers.

.DESCRIPTION
    The script disables weak ciphers to enhance system security. It enforces the following registry configurations:
    
        - Triple DES 168 (Sweet32 vulnerability mitigation)
        - DES 56/56
        - RC4 variants
        - RC2 variants
    
    Each cipher is evaluated and remediated as needed.

.NOTES
    All parameters are predefined.
    A device restart is required after applying the worklet.

.LINK
    https://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2016-2183

#>

###################################################
# PREDEFINED DESIRED REGISTRY CONFIGURATIONS

$registryInputs = @(
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\Triple DES 168/168'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\DES 56/56'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 40/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 56/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC2 128/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 40/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 56/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 64/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    },
    @{
        Path      = 'SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Ciphers\RC4 128/128'
        Name      = 'Enabled'
        Value     = '0'
        ValueType = 'Dword'
    }
)

###################################################
# DEFINE VERBOSITY PREFERENCE

# Uncommenting $VerbosePreference will show additional output in your Activity Log.
# This can be used for troubleshooting purposes.
# $VerbosePreference = 'Continue'

###################################################

# Defining testRegistry function
function testRegistry {
    [ OutputType ( [ bool ] ) ]
    param (
        [ Parameter ( Position = 0, Mandatory = $true ) ]
        [ String ] $Path,

        [ Parameter ( Position = 1, Mandatory = $false ) ]
        [ String ] $Name,

        [ Parameter ( Position = 2, Mandatory = $false ) ]
        [ String ] $Value,

        [ Parameter ( Position = 3, Mandatory = $false ) ]
        [ ValidateSet ( 'None', 'String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord' ) ]
        [ String ] $ValueType
    )

    if ( [ System.Environment ]::Is64BitOperatingSystem ) {
        $View = 'Registry64'
    } else {
        $View = 'Registry32'
    }

    try {
        $baseKey = [ Microsoft.Win32.RegistryKey ]::OpenBaseKey( [ Microsoft.Win32.RegistryHive ]::LocalMachine, [ Microsoft.Win32.RegistryView ]::$View )
        $subKey = $baseKey.OpenSubKey( $Path )
        $Exists = $false

        if ( !$subKey ) { return $Exists }

        if ( $Name -and ( $Name -notin $subKey.GetValueNames() ) ) {
            Write-Verbose "$Name was not found under $Path."
            return $Exists
        }

        if ( $Value -and ($subKey.GetValue( $Name ) -ne $Value) ) {
            Write-Verbose "$Name value does not match the expected value of $Value."
            return $Exists
        }

        if ( $ValueType -and ($subKey.GetValueKind( $Name ).ToString() -ne $ValueType) ) {
            Write-Verbose "$Name type does not match the expected type of $ValueType."
            return $Exists
        }

        $Exists = $true
        return $Exists
    } catch {
        Write-Error "An error occurred while accessing the registry: $( $_.Exception.Message )"
        exit 1
    }
}

# Defining setRegistry Function
function setRegistry {
    param (
        [ Parameter ( Position = 0, Mandatory = $true ) ]
        [ String] $Path,

        [ Parameter ( Position = 1, Mandatory = $false ) ]
        [ String] $Name,

        [ Parameter ( Position = 2, Mandatory = $false ) ]
        [ String ] $Value,

        [ Parameter ( Position = 3, Mandatory = $false ) ]
        [ ValidateSet ( 'None', 'String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord' ) ]
        [ String ] $ValueType
    )

    if ( [ System.Environment ]::Is64BitOperatingSystem ) {
        $View = 'Registry64'
    } else {
        $View = 'Registry32'
    }

    try {
        $baseKey = [ Microsoft.Win32.RegistryKey ]::OpenBaseKey( [ Microsoft.Win32.RegistryHive ]::LocalMachine, [ Microsoft.Win32.RegistryView ]::$View )
        $subKey = $baseKey.CreateSubKey( $Path )
        $subKey.SetValue( $Name, $Value, ( [ Microsoft.Win32.RegistryValueKind ] $ValueType ) )
        $subKey.Close()
        Write-Output "The desired registry configuration has been set."
    } catch {
        Write-Error "An error occurred while remediating the registry: $( $_.Exception.Message )"
        exit 2
    }
}

# Check and remediate
$remediationInputs = @()
foreach ( $input in $registryInputs ) {
    $result = testRegistry @input
    if ( -not $result ) { $remediationInputs += $input }
}

if ( $remediationInputs.Count -gt 0 ) {
    Write-Verbose 'Running setRegistry function.'
    foreach ( $input in $remediationInputs ) { setRegistry @input }
}

Write-Output 'All specified ciphers have been disabled. Device is compliant.'
exit 0
