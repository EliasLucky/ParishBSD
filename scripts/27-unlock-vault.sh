#!/bin/sh
# 27-unlock-vault.sh - unlock a vault and start its jail.
#
# Usage: sh 27-unlock-vault.sh <vault-name>
#
# Loads the ZFS key (prompting if needed), mounts the encrypted dataset,
# and starts the jail. If the jail is already running, it just confirms
# the vault is unlocked.

set -eu

name="${1:?usage: 27-unlock-vault.sh <vault-name>}"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

ds="zroot/vault-data/$name"

zfs list "$ds" >/dev/null 2>&1 || err "no encrypted dataset $ds (was the vault created?)"

# Load key if not already loaded.
if ! zfs get -H -o value keystatus "$ds" 2>/dev/null | grep -q '^available$'; then
	log "Loading key for $ds"
	zfs load-key "$ds" || err "failed to load key"
else
	log "Key already loaded for $ds"
fi

# Mount if not already mounted.
if ! mount | grep -q "on /zroot/vault-data/$name "; then
	log "Mounting $ds"
	zfs mount "$ds" || err "failed to mount"
fi

log "Vault $name is unlocked and mounted"

# Start the jail if it isn't already running.
if jls name 2>/dev/null | grep -qx "$name"; then
	log "Jail $name is already running"
else
	log "Starting jail $name"
    service jail start "$name" || err "failed to start jail"
fi

log "Done."
