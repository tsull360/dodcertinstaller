# DoD Cert Installer
These are a series of platform specific scripts used for installing the root and intermediate certificates used for PKI deployments.

Each script reaches out to DISA and downloads the most recent file of certificates. They are then extracted and installed as appropriate.

The Windows and Mac versions were written by me. I used Claude to help convert my Mac version into a Linux version.

The Mac version has one annoyance: each cert is prompted for permissions when being added to the keychain.