#!/bin/sh
# 27-unlock-vault.sh - unlock a vault and start its jail.
#
# Usage: sh 27-unlock-vault.sh <vault-name>
#
# Loads the ZFS key (prompting if needed), mounts the encrypted
# dataset, and starts the jail. If the vault is already unlocked and
# its jail is already running, this is a no-op.
#
# Safe to run multiple times.
set -eu

name="${1:?usage: 27-unlock-vault.sh <vault-name>}"

log() { printf '    %s\n' "$*"; }
row() { printf '    %-22s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

ds="zroot/vault-data/$name"
mnt="/zroot/vault-data/$name"

zfs list "$ds" >/dev/null 2>&1 || err "no encrypted dataset $ds"

# --- Load the key if it isn't already loaded ---
keystatus="$(zfs get -H -o value keystatus "$ds" 2>/dev/null || echo 'unknown')"
case "$keystatus" in
	available)
		row "key" "already loaded"
		;;
	unavailable)
		log "Loading key for $ds (enter passphrase when prompted)"
		zfs load-key "$ds" || err "failed to load key (wrong passphrase?)"
		row "key" "loaded"
		;;
	*)
		err "unexpected keystatus for $ds: $keystatus"
		;;
esac

# --- Mount if not already mounted ---
if mount | grep -q "on $mnt "; then
	row "mount" "already mounted"
else
	zfs mount "$ds" || err "cannot mount $ds"
	row "mount" "$mnt"
fi

# --- Start the jail if not already running ---
if jls name 2>/dev/null | grep -qx "$name"; then
	row "jail" "already running"
else
	log "Starting jail $name"
	service jail start "$name" || err "failed to start jail $name"
	row "jail" "started"
fi

log "Vault '$name' is unlocked and running."
