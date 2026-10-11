#!/bin/sh
# provision.sh  set up the compatibility jail.
# Installs wine, linux compatibility, and the helper tools.
set -eu

log() { printf '    [apps-compatible] %s\n' "$*"; }

# linux compatibility layer.
sysrc linux_enable=YES

# Install wine and 32-bit libraries.
pkg install -y wine wine-mono wine-gecko winetricks || true
pkg install -y linux_base-c7 linux_libc6-shim || true

# exchange directory inside the jail.
mkdir -p /exchange
chmod 0777 /exchange

log "Compatibility environment ready."
