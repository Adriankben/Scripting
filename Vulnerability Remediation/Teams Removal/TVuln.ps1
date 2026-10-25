# Bypass execution policy for this script
$originalPolicy = Get-ExecutionPolicy
Set-ExecutionPolicy Bypass -Scope Process -Force

try {
    # Define the path to Teams executable for user profiles
    $teamsPath = "AppData\Local\Microsoft\Teams\current\Teams.exe"
    $basePath = "C:\Users"

    # Define the version to compare against
    $compareVersion = [System.Version]::Parse("1.6.00.26474")

    # Get all user directories
    $userDirectories = Get-ChildItem -Path $basePath -Directory

    # Initialize a list to store results and flags for found status
    $results = @()
    $teamsFound = $false
    $olderVersionFound = $false

    # Loop through each user directory
    foreach ($userDir in $userDirectories) {
        # Build the full path to the Teams executable for the current user
        $fullPath = Join-Path -Path $userDir.FullName -ChildPath $teamsPath
        
        # Check if the Teams executable exists
        if (Test-Path $fullPath) {
            # Get the file version
            $fileVersionInfo = (Get-Item $fullPath).VersionInfo
            $version = [System.Version]::Parse($fileVersionInfo.FileVersion)

            $results += "User Profile: $($userDir.Name) - Teams.exe found at: $fullPath, Version: $version"
            $teamsFound = $true  # Set flag to true

            # Compare versions
            if ($version -lt $compareVersion) {
                $olderVersionFound = $true

                # Stop Teams if running (this might not work in SYSTEM context)
                $teamsProcess = Get-Process -Name "Teams" -ErrorAction SilentlyContinue
                if ($teamsProcess) {
                    Stop-Process -Id $teamsProcess.Id -Force -ErrorAction SilentlyContinue
                }

                # Remove the outdated Teams executable
                Remove-Item -Path $fullPath -Force
                $results += "Removed outdated Teams.exe for user: $($userDir.Name)"
            }
        } else {
            $results += "User Profile: $($userDir.Name) - Teams.exe not found"
        }
    }

    # Log results for review (optional)
    # $results | Out-File "C:\Automox\TeamsRemediationResults.txt"

    # Set the exit code based on whether Teams was found and version comparison
    if ($teamsFound) {
        if ($olderVersionFound) {
            [System.Environment]::ExitCode = 1  # Found and deleted older version
        } else {
            [System.Environment]::ExitCode = 0  # Found up-to-date version
        }
    } else {
        [System.Environment]::ExitCode = 0  # No matches found
    }

    # Output results (optional)
    #$results | ForEach-Object { Write-Output $_ }

} finally {
    # Restore original execution policy
    Set-ExecutionPolicy $originalPolicy -Scope Process -Force
}