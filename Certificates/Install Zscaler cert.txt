$CertPath = "C:\Users\ab\Documents\Cert\Zscaler.crt"
$CertStore = "Cert:\LocalMachine\Root"  # Change if needed (e.g., "Cert:\LocalMachine\My")

Import-Certificate -FilePath $CertPath -CertStoreLocation $CertStore
