# DoD Cert Installer
These are a series of platform specific scripts used for installing the root and intermediate certificates used for PKI deployments.

Each script reaches out to DISA and downloads the most recent file of certificates. They are then extracted and installed as appropriate.

The Windows and Mac versions were written by me. I used Claude to help convert my Mac version into a Linux version.

The Mac version has one annoyance: each cert is prompted for permissions when being added to the keychain.

## Run directly from GitHub

The following commands download the script directly from GitHub and run it without cloning the repository first.

### macOS
The macOS script installs certs into the current user’s login keychain so it avoids repeated admin prompts.

```bash
curl -fsSL https://raw.githubusercontent.com/zonal-coyote-9/dodcertinstaller/main/OSCertInstallScript-MacOS.sh | bash
```

### Fedora / Linux
```bash
curl -fsSL https://raw.githubusercontent.com/zonal-coyote-9/dodcertinstaller/main/OSCertInstallScript-Fedora.sh | sudo bash
```

### Windows (PowerShell as Administrator)
```powershell
powershell -ExecutionPolicy Bypass -Command "Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/zonal-coyote-9/dodcertinstaller/main/OSCertInstallScript-Windows.ps1' -OutFile \"$env:TEMP\OSCertInstallScript-Windows.ps1\"; & \"$env:TEMP\OSCertInstallScript-Windows.ps1\""
```

## Local usage

If you prefer to download the script first, you can also run the scripts from a local checkout:

### macOS
```bash
sudo bash OSCertInstallScript-MacOS.sh
```

### Fedora / Linux
```bash
sudo bash OSCertInstallScript-Fedora.sh
```

### Windows
```powershell
.\OSCertInstallScript-Windows.ps1
```