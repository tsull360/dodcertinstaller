#!/usr/bin/env bash
set -euo pipefail

# Name: OSCertInstaller-Linux-Fx.sh
# Usage: sudo bash OSCertInstaller-Linux-Fx.sh
# Version: 1.2
# Author: tsull360@outlook.com (adapted for Ubuntu/Fedora + Firefox NSS)
# Info: Installs DoD Root/CA certs into system trust store and Firefox profiles.
#       Includes dependency checks + automatic installation (apt/dnf).

echo "DoD Certificate Installer Script (Ubuntu/Fedora + Firefox) with dependency install"

WORKDIR="${WORKDIR:-/tmp/dod-certs}"
ZIP_URL="https://dl.dod.cyber.mil/wp-content/uploads/pki-pke/zip/unclass-certificates_pkcs7_DoD.zip"

# Firefox trust flags (NSS). "C,," = trusted CA for SSL.
FF_TRUST_FLAGS="${FF_TRUST_FLAGS:-C,,}"

need() { command -v "$1" >/dev/null 2>&1; }
die() { echo "ERROR: $*" >&2; exit 1; }

if [[ $EUID -ne 0 ]]; then
  die "Please run as root (e.g., sudo $0)"
fi

# --- Detect package manager / distro family ---
PKG_MGR=""
if need apt-get; then
  PKG_MGR="apt"
elif need dnf; then
  PKG_MGR="dnf"
else
  die "Unsupported system: neither apt-get nor dnf found. Install deps manually and re-run."
fi

# --- Determine system trust tooling + destination directory ---
TRUST_TOOL=""
DEST_DIR=""
if need update-ca-certificates; then
  TRUST_TOOL="update-ca-certificates"
  DEST_DIR="/usr/local/share/ca-certificates/dod"
elif need update-ca-trust; then
  TRUST_TOOL="update-ca-trust"
  DEST_DIR="/etc/pki/ca-trust/source/anchors"
else
  # We'll install ca-certificates below, then re-check.
  TRUST_TOOL=""
  DEST_DIR=""
fi

# --- Dependency maps ---
APT_PKGS=(curl unzip openssl ca-certificates libnss3-tools gawk coreutils findutils sed grep)
DNF_PKGS=(curl unzip openssl ca-certificates nss-tools gawk coreutils findutils sed grep)

install_packages() {
  echo "Installing required packages using $PKG_MGR ..."
  if [[ "$PKG_MGR" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y "${APT_PKGS[@]}"
  else
    dnf install -y "${DNF_PKGS[@]}"
  fi
}

# --- Check required binaries; install if missing ---
REQUIRED_BINS=(curl unzip openssl awk sed grep find)
MISSING=()

for b in "${REQUIRED_BINS[@]}"; do
  need "$b" || MISSING+=("$b")
done

# Trust tool is required too (but comes from ca-certificates)
if ! need update-ca-certificates && ! need update-ca-trust; then
  MISSING+=("ca-trust-tooling")
fi

# certutil is optional-ish but required for Firefox coverage
if ! need certutil; then
  MISSING+=("certutil")
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "Missing dependencies detected: ${MISSING[*]}"
  install_packages
fi

# --- Re-evaluate trust tool now that packages may be installed ---
if need update-ca-certificates; then
  TRUST_TOOL="update-ca-certificates"
  DEST_DIR="/usr/local/share/ca-certificates/dod"
elif need update-ca-trust; then
  TRUST_TOOL="update-ca-trust"
  DEST_DIR="/etc/pki/ca-trust/source/anchors"
else
  die "Still unable to find update-ca-certificates or update-ca-trust after installing packages."
fi

HAS_CERTUTIL=0
if need certutil; then
  HAS_CERTUTIL=1
else
  echo "NOTE: certutil still not found; Firefox profile import will be skipped."
fi

echo "Package manager: $PKG_MGR"
echo "Trust update tool: $TRUST_TOOL"
echo "System trust install dir: $DEST_DIR"
echo "Firefox certutil: $([[ "$HAS_CERTUTIL" == "1" ]] && echo "yes" || echo "no")"

# --- Prepare working dirs ---
mkdir -p "$WORKDIR"/{zip,extracted,individual,selected}
rm -rf "$WORKDIR/zip/"* "$WORKDIR/extracted/"* "$WORKDIR/individual/"* "$WORKDIR/selected/"* || true

# --- Download and unzip ---
echo "Downloading DoD certificate bundle..."
curl -fsSL "$ZIP_URL" -o "$WORKDIR/zip/DoDCerts.zip"

echo "Extracting..."
unzip -q -o "$WORKDIR/zip/DoDCerts.zip" -d "$WORKDIR/extracted"

# --- Find p7b files ---
mapfile -t P7B_FILES < <(find "$WORKDIR/extracted" -type f -name "*.p7b" | sort)
[[ ${#P7B_FILES[@]} -gt 0 ]] || die "No .p7b files found after extraction (bundle layout may have changed)."

# --- Helpers ---
sanitize_name() {
  local s="$1"
  s="$(echo "$s" | tr -cd '[:alnum:]. _-')"
  s="$(echo "$s" | sed 's/[[:space:]]\+/_/g')"
  echo "$s"
}

get_cn() {
  local cert="$1"
  local subj cn
  subj="$(openssl x509 -in "$cert" -noout -subject 2>/dev/null || true)"
  cn="$(echo "$subj" | sed -n 's/.*CN[[:space:]]*=[[:space:]]*\([^,/]*\).*/\1/p' | head -n 1)"
  if [[ -z "$cn" ]]; then
    cn="$(openssl x509 -in "$cert" -noout -hash 2>/dev/null || echo "unknown")"
  fi
  echo "$cn"
}

# --- Extract individual certs as PEM ---
echo "Extracting certificates from PKCS#7 bundles..."
for p7b in "${P7B_FILES[@]}"; do
  echo "  Processing: $p7b"

  # Try DER first, then PEM
  if ! openssl pkcs7 -inform DER -in "$p7b" -print_certs > "$WORKDIR/extracted/cert-stream.pem" 2>/dev/null; then
    openssl pkcs7 -inform PEM -in "$p7b" -print_certs > "$WORKDIR/extracted/cert-stream.pem"
  fi

  # Split into individual cert PEM files
  awk -v outdir="$WORKDIR/individual" '
    /-----BEGIN CERTIFICATE-----/ {n++; fn=sprintf("%s/cert-%06d.pem", outdir, n)}
    { if (fn) print > fn }
    /-----END CERTIFICATE-----/ { fn="" }
  ' "$WORKDIR/extracted/cert-stream.pem"
done

TOTAL=$(find "$WORKDIR/individual" -maxdepth 1 -type f -name "cert-*.pem" | wc -l | tr -d ' ')
echo "Total individual cert files extracted: $TOTAL"

# --- Select only Root and CA-* certs ---
echo "Selecting Root and CA-* certificates..."
installed=0
skipped=0

for certfile in "$WORKDIR/individual"/cert-*.pem; do
  [[ -f "$certfile" ]] || continue
  cn="$(get_cn "$certfile")"

  if [[ "$cn" == *Root* || "$cn" == *CA-* ]]; then
    safe="$(sanitize_name "$cn")"
    out="$WORKDIR/selected/DoD_${safe}.crt"
    cp -f "$certfile" "$out"
    chmod 0644 "$out"
    installed=$((installed + 1))
  else
    skipped=$((skipped + 1))
  fi
done

echo "Selected for install: $installed (skipped: $skipped)"
[[ $installed -gt 0 ]] || die "No matching Root/CA-* certs selected."

# --- Install into system trust store ---
echo "Installing into system trust store..."
mkdir -p "$DEST_DIR"
cp -f "$WORKDIR/selected/"*.crt "$DEST_DIR"/
chmod 0644 "$DEST_DIR/"*.crt

echo "Updating system trust store..."
if [[ "$TRUST_TOOL" == "update-ca-trust" ]]; then
  update-ca-trust extract
else
  update-ca-certificates
fi
echo "System trust store updated."

# --- Firefox coverage: import into NSS DB for each profile we can find ---
find_firefox_profiles() {
  local home="$1"
  # Classic
  find "$home/.mozilla/firefox" -maxdepth 1 -type d -name "*.default*" 2>/dev/null || true
  find "$home/.mozilla/firefox" -maxdepth 1 -type d -name "*.release*" 2>/dev/null || true

  # Snap (Ubuntu)
  find "$home/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -type d -name "*.default*" 2>/dev/null || true
  find "$home/snap/firefox/common/.mozilla/firefox" -maxdepth 1 -type d -name "*.release*" 2>/dev/null || true

  # Flatpak
  find "$home/.var/app/org.mozilla.firefox/.mozilla/firefox" -maxdepth 1 -type d -name "*.default*" 2>/dev/null || true
  find "$home/.var/app/org.mozilla.firefox/.mozilla/firefox" -maxdepth 1 -type d -name "*.release*" 2>/dev/null || true
}

import_into_profile() {
  local profile_dir="$1"
  local cert_path="$2"
  local nickname="$3"
  local db="sql:${profile_dir}"

  # If nickname exists, delete then re-add
  if certutil -L -d "$db" 2>/dev/null | awk '{print $1}' | grep -Fxq "$nickname"; then
    certutil -D -d "$db" -n "$nickname" >/dev/null 2>&1 || true
  fi

  certutil -A -d "$db" -n "$nickname" -t "$FF_TRUST_FLAGS" -i "$cert_path" >/dev/null
}

if [[ "$HAS_CERTUTIL" == "1" ]]; then
  echo "Importing into Firefox profiles (NSS)..."

  USER_HOMES=("/root")
  while IFS= read -r d; do USER_HOMES+=("$d"); done < <(find /home -mindepth 1 -maxdepth 1 -type d 2>/dev/null || true)

  fx_profiles=0
  fx_imports=0

  for home in "${USER_HOMES[@]}"; do
    [[ -d "$home" ]] || continue
    while IFS= read -r prof; do
      [[ -d "$prof" ]] || continue
      fx_profiles=$((fx_profiles + 1))
      echo "  Profile: $prof"

      for cert in "$WORKDIR/selected/"*.crt; do
        cn="$(get_cn "$cert")"
        nick="DoD - $(sanitize_name "$cn")"
        nick="${nick:0:120}"
        if import_into_profile "$prof" "$cert" "$nick"; then
          fx_imports=$((fx_imports + 1))
        fi
      done
    done < <(find_firefox_profiles "$home")
  done

  echo "Firefox profiles found: $fx_profiles"
  echo "Firefox cert imports completed: $fx_imports"
else
  echo "Skipping Firefox import (certutil not available)."
fi

echo "Complete."
echo "Workdir: $WORKDIR"
echo "System store dir: $DEST_DIR"