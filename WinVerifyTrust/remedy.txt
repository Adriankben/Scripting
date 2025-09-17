
###################################################
# DEFINING DESIRED REGISTRY CONFIGURATION

$registryInputs = (

	# Registry Configuration 32-Bit
	@{
		Path	  = 'SOFTWARE\Microsoft\Cryptography\Wintrust\Config'
		Name	  = 'EnableCertPaddingCheck'
		Value	  = '1'
		ValueType = 'String'
	},

	# Registry Configuration 64-Bit
	@{
		Path	  = 'SOFTWARE\Wow6432Node\Microsoft\Cryptography\Wintrust\Config'
		Name	  = 'EnableCertPaddingCheck'
		Value	  = '1'
		ValueType = 'String'
	}

)
###################################################

# Defining Test-Registry function
function Test-Registry
{
	[OutputType([bool])]
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string]$Path,
		[Parameter(Position = 1, Mandatory = $false)]
		[string]$Name,
		[Parameter(Position = 2, Mandatory = $false)]
		[string]$Value,
		[Parameter(Position = 3, Mandatory = $false)]
		[ValidateSet('None', 'String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
		[string]$ValueType
	)

	# Determine OS Architecture
	if ([System.Environment]::Is64BitOperatingSystem)
	{
		$View = 'Registry64'
	}

	else
	{
		$View = 'Registry32'
	}

	try
	{
		$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::$View)
		$subKey = $baseKey.OpenSubKey($Path)
		$Exists = @($false)

		if (!$subKey)
		{
			return $Exists
		}

		if ($Name -and ($Name -notin $subKey.GetValueNames()))
		{
			Write-Verbose "$Name was not found under $Path."
			return $Exists
		}

		if ($Value)
		{
			$detectedValue = $subKey.GetValue($Name)
			if ($null -eq $detectedValue)
			{
				Write-Verbose "$Name was found under $Path but it does not have a value."
				return $Exists
			}

			if ($detectedValue -ne $Value)
			{
				Write-Verbose "$Name was found under $Path but the value does not match the expected value of $Value."
				return $Exists
			}
		}

		if ($ValueType)
		{
			$detectedValueType = $subKey.GetValueKind($Name).ToString()
			if ($detectedValueType -ne $ValueType)
			{
				Write-Verbose "$Name was found under $Path but the type does not match the expected type of $ValueType."
				return $Exists
			}
		}

		$Exists = $true
		return $Exists
	}

	catch
	{
		Write-Error "An error occurred while accessing the registry: $($_.Exception.Message)"
		Exit 2
	}
}

# Defining Set-Registry Function
function Set-Registry
{
	param (
		[Parameter(Position = 0, Mandatory = $true)]
		[string]$Path,
		[Parameter(Position = 1, Mandatory = $false)]
		[string]$Name,
		[Parameter(Position = 2, Mandatory = $false)]
		[string]$Value,
		[Parameter(Position = 3, Mandatory = $false)]
		[ValidateSet('None', 'String', 'ExpandString', 'Binary', 'DWord', 'MultiString', 'QWord')]
		[string]$ValueType
	)

	# Determine OS Architecture
	if ([System.Environment]::Is64BitOperatingSystem)
	{
		$View = 'Registry64'
	}

	else
	{
		$View = 'Registry32'
	}

	try
	{
		$baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine, [Microsoft.Win32.RegistryView]::$View)
		$subKey = $baseKey.CreateSubKey($Path)
		$subKey.SetValue($Name, $Value, ([Microsoft.Win32.RegistryValueKind]$ValueType))
		$subKey.Close()
		Write-Output "The desired registry configuration for $Name has been set."
	}

	catch
	{
		Write-Error "An error occurred while remediating the registry: $($_.Exception.Message)"
		Exit 2
	}
}

# Run Test-Registry function to test current registry configuration vs the desired state configuration.
ForEach ($input in $registryInputs)
{
	If (-not (Test-Registry @input))
	{
		# Run Set-Registry function against non-compliant input
		Set-Registry @input
	}
}
Write-Output "Device is compliant with the desired registry configuration."
Exit 0

Write-Output "Device is compliant with the desired registry configuration."
Exit 0