#!/bin/sh
# 28-lock-vault.sh - stop a vault's jail and lock its data.
set -eu
name="${1:?usage: 28-lock-vault.sh <vault-name>}"
log() { printf '    %s\n' "$*"; }

[ "$(id -u)" -eq 0 ] || { echo "must be root" >&2; exit 1; }

if jls name 2>/dev/null | grep -qx "$name"; then
	log "Stopping jail $name"
	service jail stop "$name" || true
fi

ds="zroot/vault-data/$name"
if zfs list "$ds" >/dev/null 2>&1; then
	log "Unmounting and unloading key for $ds"
	zfs unmount "$ds" 2>/dev/null || true
	zfs unload-key "$ds" 2>/dev/null || true
fi
log "Vault $name is locked"
