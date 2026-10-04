#!/bin/sh
# 26-create-vault-data.sh = create an encrypted ZFS dataset for a vault.
#
# Usage: sh 26-create-vault-data.sh <vault-name> [keyfile]
#
# Two modes:
#   - Default (passphrase): prompts for a passphrase. Required at every boot.
#   - With keyfile argument: generates a random key, stores it at <keyfile>
#     with 0600 permissions, and loads it automatically at boot.
#
# The keyfile mode is convenient but less secure — anyone with root who
# can read the keyfile can unlock the vault. Use it only on machines that
# are physically secure.

set -eu

name="${1:?usage: 26-create-vault-data.sh <vault-name> [keyfile]}"
keyfile="${2:-}"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

ds="zroot/vault-data/$name"
mnt="/zroot/vault-data/$name"

if zfs list "$ds" >/dev/null 2>&1; then
	log "Dataset $ds already exists - nothing to do"
	exit 0
fi

# Ensure the parent exists.
zfs list zroot/vault-data >/dev/null 2>&1 || zfs create -p zroot/vault-data

if [ -n "$keyfile" ]; then
	# Keyfile mode
	log "Creating keyfile at $keyfile"
	umask 077
	dd if=/dev/random of="$keyfile" bs=32 count=1 2>/dev/null
	chmod 0600 "$keyfile"

	log "Creating encrypted dataset $ds (keyfile mode)"
	zfs create \
		-o encryption=on \
		-o keyformat=raw \
		-o keylocation="file://$keyfile" \
		-o mountpoint="$mnt" \
		"$ds"
else
	# Passphrase mode
	log "Creating encrypted dataset $ds (passphrase mode)"
	log "You will be prompted for a passphrase. Choose something strong."
	log "This passphrase will be required at every boot to unlock the vault."
	echo

	zfs create \
		-o encryption=on \
		-o keyformat=passphrase \
		-o keylocation=prompt \
		-o mountpoint="$mnt" \
		"$ds"
fi

log "Created $ds (mounted at $mnt)"

chmod 0700 "$mnt"
chown root:wheel "$mnt"

log "Done."
if [ -z "$keyfile" ]; then
	log "Vault is now UNLOCKED. To lock it:"
	log "  zfs unmount $ds && zfs unload-key $ds"
fi
