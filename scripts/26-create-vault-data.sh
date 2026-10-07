#!/bin/sh
# 26-create-vault-data.sh — create the encrypted ZFS dataset for a vault.
#
# Usage: sh 26-create-vault-data.sh <vault-name> [keyfile]
#
# Two modes:
#   Passphrase mode (default):
#       Prompts for a passphrase. Required at every boot to unlock.
#       This is the secure default — the key never touches disk.
#
#   Keyfile mode (with <keyfile> argument):
#       Generates a random 32-byte key, stores it at <keyfile> with
#       0600 permissions, and configures ZFS to load it automatically
#       at boot. Convenient, but only as safe as the keyfile's
#       location. Use only on physically secured machines.
#
# Idempotent: if the dataset already exists, prints a message and exits.
set -eu

name="${1:?usage: 26-create-vault-data.sh <vault-name> [keyfile]}"
keyfile="${2:-}"

log() { printf '    %s\n' "$*"; }
row() { printf '    %-22s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v zfs >/dev/null 2>&1 || err "zfs not found"

ds="zroot/vault-data/$name"
mnt="/zroot/vault-data/$name"

if zfs list "$ds" >/dev/null 2>&1; then
	row "dataset" "$ds already exists"
	exit 0
fi

# Ensure the parent exists.
zfs list zroot/vault-data >/dev/null 2>&1 || \
	zfs create -p zroot/vault-data || err "cannot create zroot/vault-data"

# ---------------------------------------------------------------- create
if [ -n "$keyfile" ]; then
	# -------------------------------------------------- keyfile mode
	log "Creating keyfile at $keyfile"
	umask 077
	dd if=/dev/random of="$keyfile" bs=32 count=1 2>/dev/null
	chmod 0600 "$keyfile"
	row "keyfile" "$keyfile"

	log "Creating encrypted dataset (keyfile mode)"
	zfs create \
		-o encryption=on \
		-o keyformat=raw \
		-o keylocation="file://$keyfile" \
		-o mountpoint="$mnt" \
		"$ds" || err "zfs create failed"
else
	# -------------------------------------------------- passphrase mode
	log "Creating encrypted dataset (passphrase mode)"
	log "You will be prompted for a passphrase. Choose something strong."
	log "This passphrase is required at every boot to unlock the vault."
	log "There is no recovery if it is lost."
	echo

	zfs create \
		-o encryption=on \
		-o keyformat=passphrase \
		-o keylocation=prompt \
		-o mountpoint="$mnt" \
		"$ds" || err "zfs create failed"
fi

# ---------------------------------------------------------------- perms
chmod 0700 "$mnt"
chown root:wheel "$mnt"

row "dataset" "$ds"
row "mount"   "$mnt"
row "mode"    "$([ -n "$keyfile" ] && echo keyfile || echo passphrase)"

if [ -z "$keyfile" ]; then
	log "Vault is UNLOCKED. To lock it now:"
	log "    zfs unmount $ds && zfs unload-key $ds"
else
	log "Vault is UNLOCKED and will auto-unlock at boot."
fi
