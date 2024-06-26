#!/bin/bash

# Name: OSCertInstaller-OSX.sh
# Version: 1.0
# Author: Tim Sullivan
# Info: Bash script for installing DoD root certificates onto an Apple Mac.
#       Tested on Apple Silicon and Intel based Big Sur Mac's.

echo "DoD Certificate Installer Script"

# Preparing needed working folders
{
    mkdir /tmp/certs
    mkdir /tmp/certs/split
    mkdir /tmp/certs/fixed
} &> /dev/null

cd /tmp/certs

# Downloading certificates, extracting them
curl -sS https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip > DoDCerts.zip
unzip -u -q DoDCerts.zip
#rm DoDCerts.zip

# Converting certs into workable format, extracting from supplied p7b format to cer format, then to
# individual cert files.
for filename in /tmp/certs/certificates_pkcs7_v5_13_dod/*.p7b; do
    echo "Preparing certificates from the following file: $filename"
    #openssl pkcs7 -inform PEM -outform PEM -in $filename -print_certs > /tmp/certs/certcat.cer
    openssl pkcs7 -in $filename -inform der -print_certs > /tmp/certs/certcat.cer
    split -p "subject=" /tmp/certs/certcat.cer /tmp/certs/split/individual-
done

# Renaming the individual cert files into their subject names
for cert in /tmp/certs/split/*; do
    line=$(head -n 1 $cert)
    echo "Subject: $line"
    newfile=${line##*CN=}
    echo "Subject CN: $newfile"
    mv $cert "/tmp/certs/fixed/$newfile.cer"
done

# Loop through the collection of certificates. Installing each one into the system root store
for CertName in /tmp/certs/fixed/*Root*.cer; do
    echo "Importing the following cert info the System Keychain: $CertName"
    security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain "$CertName"
done

for CertName in /tmp/certs/fixed/*CA-*.cer; do
    echo "Importing the following cert info the System Keychain: $CertName"
    security add-trusted-cert -d -r trustAsRoot -k /Library/Keychains/System.keychain "$CertName"
done

echo "Cleaning up working folders"
#rm -rf /tmp/certs

echo "Script complete!"