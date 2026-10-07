#!/bin/sh
# 28-lock-vault.sh - stop a vault's jail and lock its data.
#
# Usage: sh 28-lock-vault.sh <vault-name>
#
# Stops the jail (if running), unmounts the encrypted dataset, and
# unloads its key. After this, the vault's data is unreadable until
# 27-unlock-vault.sh is run again.
#
# Safe to run multiple times.
set -eu

name="${1:?usage: 28-lock-vault.sh <vault-name>}"

log() { printf '    %s\n' "$*"; }
row() { printf '    %-22s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

ds="zroot/vault-data/$name"

# --- Stop the jail if running ---
if jls name 2>/dev/null | grep -qx "$name"; then
	log "Stopping jail $name"
	service jail stop "$name" || row "jail" "stop returned non-zero"
	row "jail" "stopped"
else
	row "jail" "not running"
fi

# --- Unmount and unload the key ---
if zfs list "$ds" >/dev/null 2>&1; then
	if mount | grep -q "on /zroot/vault-data/$name "; then
		zfs unmount "$ds" || row "mount" "unmount failed"
		row "mount" "unmounted"
	else
		row "mount" "already unmounted"
	fi

	keystatus="$(zfs get -H -o value keystatus "$ds" 2>/dev/null || echo 'unknown')"
	if [ "$keystatus" = "available" ]; then
		zfs unload-key "$ds" || row "key" "unload failed"
		row "key" "unloaded"
	else
		row "key" "already unloaded"
	fi
else
	row "dataset" "$ds does not exist"
fi

log "Vault '$name' is locked."
