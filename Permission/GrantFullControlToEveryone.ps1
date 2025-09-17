# Define the target folder path
$FolderPath = "C:\Path"
 
# Check if the folder exists
if (-Not (Test-Path -Path $FolderPath)) {
    Write-Output "The specified folder path does not exist: $FolderPath"
    exit 1
}
 
# Set the owner of the folder to 'Everyone'
Write-Output "Changing ownership of $FolderPath and its contents to 'Everyone'..."
$Everyone = New-Object System.Security.Principal.NTAccount("Everyone")
$FolderSecurity = Get-Acl -Path $FolderPath
$FolderSecurity.SetOwner($Everyone)
Set-Acl -Path $FolderPath -AclObject $FolderSecurity
 
# Traverse all child objects and change their ownership to 'Everyone'
Get-ChildItem -Path $FolderPath -Recurse -Force | ForEach-Object {
    try {
        $ChildSecurity = Get-Acl -Path $_.FullName
        $ChildSecurity.SetOwner($Everyone)
        Set-Acl -Path $_.FullName -AclObject $ChildSecurity
        Write-Output "Ownership changed for: $($_.FullName)"
    } catch {
        Write-Output "Failed to change ownership for: $($_.FullName). Error: $_"
    }
}
 
# Get the ACL (Access Control List) of the folder
$ACL = Get-Acl -Path $FolderPath
 
# Create a new access rule for "Everyone" with Full Control
$AccessRuleFolder = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Everyone",                           # User or group
    "FullControl",                        # Permission
    "ContainerInherit, ObjectInherit",    # Apply to folders and subfolders
    "None",                               # No special flags
    "Allow"                               # Allow the permission
)
 
$AccessRuleFile = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Everyone",                           # User or group
    "FullControl",                        # Permission
    "None",                               # No inheritance flags for files
    "None",                               # No special flags
    "Allow"                               # Allow the permission
)
 
# Add the access rule to the ACL
$ACL.SetAccessRule($AccessRuleFolder)
 
# Enable inheritance and replace all child object permissions
$ACL.SetAccessRuleProtection($false, $true)
 
# Apply the modified ACL back to the root folder
Set-Acl -Path $FolderPath -AclObject $ACL
 
# Traverse all child objects and apply appropriate ACLs for files and folders
Write-Output "Applying permissions to all child objects under $FolderPath..."
Get-ChildItem -Path $FolderPath -Recurse -Force | ForEach-Object {
    try {
        # Get the current ACL of the child object
        $ChildACL = Get-Acl -Path $_.FullName
 
        # Apply different rules for files and folders
        if ($_.PSIsContainer) {
            # Folder: Apply container-specific rule
            $ChildACL.SetAccessRule($AccessRuleFolder)
        } else {
            # File: Apply file-specific rule
            $ChildACL.SetAccessRule($AccessRuleFile)
        }
 
        # Enable inheritance and replace all child object permissions
        $ChildACL.SetAccessRuleProtection($false, $true)
 
        # Set the updated ACL to the child object
        Set-Acl -Path $_.FullName -AclObject $ChildACL
        Write-Output "Permissions updated for: $($_.FullName)"
    } catch {
        Write-Output "Failed to update permissions for: $($_.FullName). Error: $_"
    }
}
 
# Final output message
Write-Output "Ownership and permissions updated successfully for the folder: $FolderPath"
Write-Output "- 'Everyone' granted full control."
Write-Output "- Permissions applied to all subfolders and files."
Write-Output "- Ownership changed to 'Everyone'."
