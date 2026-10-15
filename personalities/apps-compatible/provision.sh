#!/bin/sh
# provision.sh  set up the compatibility jail.
# Installs wine, linux compatibility, and the helper tools.
set -eu

log() { printf '    [apps-compatible] %s\n' "$*"; }

# linux compatibility layer.
sysrc linux_enable=YES


log "Compatibility environment ready."
