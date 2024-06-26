<#
.SYNOPSIS

    Script for installing root certificates for DOD systems.

.DESCRIPTION

    OSCertInstallScript-Windows.ps1 is a script that can be used to
    install certificates issued by the DoD for their systems. As a
    dedicated PKI is used, it is not natively trusted by non-DoD
    systems.

.NOTES

    Author: Tim Sullivan
    Version: 1.0
    Date: 10/04/2021
    Name: OSCertInstallScript-Windows.ps1

    CHANGE LOG
    1.0: Initial Release

.EXAMPLE
    
    .\OSCertInstallScript-Windows.ps1
#>

#Requires -RunAsAdministrator

$CertFileDownload = "https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip"
$TempPath = $env:TEMP
$CertFiles = "$TempPath\Certs"
$ExpandTemp = "$CertFiles\Expanded"

$CompTrustedRoot = "cert:\LocalMachine\Root"
$CompIntStore = "cert:\LocalMachine\CA"
$CompUnTrusted = "Cert:\LocalMachine\Disallowed"

Write-Output "DOD Roots Certificate Installer Script"
If(!(Test-Path -Path $ExpandTemp)){
    Write-Verbose "Folder missing!"
    $NewFolder = New-Item -ItemType Directory -Path $ExpandTemp -InformationAction SilentlyContinue
}
else {
    Write-Verbose "Folder not missing"
}

# Function to break out a certificate bundle into its individual files
Function Expand-Certs{
    Param(
        $certfile
    )

 $collection = New-Object Security.Cryptography.X509Certificates.X509Certificate2Collection
 $collection.Import($certfile)
 
 foreach ($cert in $collection.GetEnumerator())
 {
        $name = $cert.Subject -replace '^CN='
        if ($cert.HasPrivateKey)
        {
               $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
               [IO.File]::WriteAllBytes("$CertFiles\Expanded\$name.pfx", $bytes)
        }`
        else
        {
               $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
               [IO.File]::WriteAllBytes("$CertFiles\Expanded\$name.cer", $bytes)
        }
 }
 
 $collection.Clear()
 $collection = $null
}

# Download certificate file from DISA
Try{
    Invoke-WebRequest -Uri $CertFileDownload -OutFile $TempPath\DoDCerts.zip
    Write-Output "Cert file downloaded!"
    $DLState = "Good"
}
Catch{
    Write-Output "Error downloading cert file! Error: $($_.Exception.Message)"
    $DLState = "Error"
}

# Extract certificates from downloaded certificate zip file
If ($DLState -notlike "Error"){
    try{
        Write-Verbose "Extracting zip file contents..."
        Expand-Archive -Path $TempPath\DoDCerts.zip -DestinationPath $CertFiles -Force
        Write-Output "Cert file extracted!"
        write-Verbose "Done!"
        $ZipState = "Good"
    }
    catch{
        Write-Verbose "Error expanding zip file. Error: $($_.Exception.Message)"
        $ZipState = "Error"
    }
}else{
    Write-Output "File not downloaded. Unable to extract."
    $ZipState = "Error"
}

# Call function to extract certs from cert bundle
If ($ZipState -notlike "Error"){
    $CertFile = (Get-ChildItem -Path $CertFiles\certificates_pkcs7*\certificates_pkcs*_dod_der.p7b).FullName
    Write-Verbose "Certificate File: $CertFile"
    Expand-Certs -certfile $CertFile
    Write-Output "Certificates extracted from bundle!"
}

# Begin process of importing certificates into applicable store
# Define type of cert, root or intermediate
$Roots = get-childitem -Path $ExpandTemp -Filter "*Root*"
$NonRoots = Get-ChildItem -Path $ExpandTemp -Exclude "*Root*"

# Import root certs
Foreach ($RootCert in $Roots){
    Write-Verbose "Root Cert: $($RootCert.Fullname)"
    $ImpStatus = Import-Certificate -FilePath $($RootCert.Fullname) -CertStoreLocation $CompTrustedRoot
    Write-Output "Root certs installed!"
}

# Import intermediate certs
Foreach ($IntCert in $NonRoots){
    Write-Verbose "Int Cert: $($IntCert.FullName)"
    $Impstatus = Import-Certificate -FilePath $($IntCert.FullName) -CertStoreLocation $CompIntStore
    Write-Output "Intermediate certs installed!"
}
Remove-Item -Path $CertFiles -Force -Recurse
Write-Output "Script complete!"