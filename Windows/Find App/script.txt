# Define the partial name pattern for the Java Development Kit to target
$appNamePattern = "java* 8*";

# Use WMI to find and uninstall any app that matches the pattern
$appProduct = Get-WmiObject -Class Win32_Product | Where-Object {
    $_.Name -like $appNamePattern
};

if ($appProduct) {
    foreach ($product in $appProduct) {
        Write-Host "Uninstalling Application: $($product.Name)"
        $product.Uninstall() | Out-Null
        Write-Host "App uninstallation completed for $($product.Name)."
    }
} else {
    Write-Host "Application matching pattern '$appNamePattern' not found."
};
