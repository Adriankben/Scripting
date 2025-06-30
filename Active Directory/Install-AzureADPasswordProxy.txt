$fileName = 'AzureADPasswordProtectionProxySetup.exe'
$custArgs = '/quiet /norestart'  # Custom arguments for the installation

# Define the path for the file
$filepath = "$env:TEMP"  # Destination directory for the EXE
$fileFullPath = Join-Path -Path $filepath -ChildPath $fileName

# Check if the EXE file exists
if (!(Test-Path -Path $fileFullPath)) {
    Write-Output "EXE file $fileName does not exist in $filepath."
    Write-Output "Attempting to copy the file from the worklet payload..."

    try {
        Copy-Item -Path (Join-Path -Path $PWD -ChildPath $fileName) -Destination $fileFullPath -Force
        Write-Output "File $fileName successfully copied to $fileFullPath."
    } catch {
        Write-Output "Failed to copy $fileName. Exiting."
        Exit 1
    }
} else {
    Write-Output "EXE file $fileName already exists at $fileFullPath."
}

# Construct the command to run the EXE installer with the custom arguments
$arglist = "$fileFullPath $custArgs"

Write-Output "Starting installation with the following command:"
Write-Output $arglist

# Run the installer
try {
    Start-Process -FilePath $fileFullPath -ArgumentList $custArgs -Wait -NoNewWindow
    Write-Output "Installation complete."
} catch {
    Write-Output "Installation failed. Check the log for details."
    Exit 1
}
