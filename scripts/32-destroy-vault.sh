#!/bin/sh
# 32-destroy-vault.sh — destroy a vault completely: jail + encrypted data.
#
# Usage: sh 32-destroy-vault.sh <name>
#
# Does what 31-destroy-jail.sh does, plus destroys the encrypted ZFS
# dataset holding the vault's data.
#
# ⚠ IRREVERSIBLE. Encrypted contents cannot be recovered after this,
#   even with the passphrase.
#
# Requires typing "destroy-<name>" as confirmation.

set -eu

name="${1:?usage: 32-destroy-vault.sh <name>}"

log()  { printf '    %s\n' "$*"; }
row()  { printf '    %-22s %s\n' "$1" "$2"; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

ds="zroot/vault-data/$name"
jailroot="/usr/local/jails/vault/$name"
container_ds="zroot/jails/containers/$name"

has_data=0
zfs list "$ds" >/dev/null 2>&1 && has_data=1

has_jail=0
{ [ -d "$jailroot" ] || zfs list "$container_ds" >/dev/null 2>&1; } && has_jail=1

if [ "$has_data" -eq 0 ] && [ "$has_jail" -eq 0 ]; then
	err "no vault named '$name' (no data, no jail)"
fi

# --- Confirmation ---
printf '\n'
printf '    This will permanently destroy:\n'
printf '\n'
if [ "$has_jail" -eq 1 ]; then
	printf '        jail:  %s\n' "$jailroot"
fi
if [ "$has_data" -eq 1 ]; then
	printf '        data:  %s (encrypted)\n' "$ds"
fi
printf '\n'
printf '    Encrypted contents are NOT recoverable after this.\n'
printf '\n'
printf '    Type exactly  destroy-%s  to proceed: ' "$name"
read -r answer

if [ "$answer" != "destroy-$name" ]; then
	log "aborted - nothing was destroyed"
	exit 0
fi

# --- Stop the jail ---
if jls name 2>/dev/null | grep -qx "$name"; then
	log "Stopping jail $name"
	service jail stop "$name" 2>/dev/null || true
	row "jail" "stopped"
else
	row "jail" "not running"
fi

# --- Destroy the encrypted data ---
if [ "$has_data" -eq 1 ]; then
	zfs unmount "$ds" 2>/dev/null || true
	zfs unload-key "$ds" 2>/dev/null || true
	zfs destroy -rf "$ds" || err "failed to destroy $ds"
	row "encrypted data" "destroyed"
fi

# --- Destroy the jail container ---
if zfs list "$container_ds" >/dev/null 2>&1; then
	zfs destroy -rf "$container_ds" || err "failed to destroy $container_ds"
	row "container" "destroyed"
elif [ -d "$jailroot" ]; then
	chflags -R 0 "$jailroot" 2>/dev/null || true
	rm -rf "$jailroot"
	row "jail root" "removed directory"
fi

# --- Remove configs ---
if [ -f "/etc/jail.conf.d/$name.conf" ]; then
	rm -f "/etc/jail.conf.d/$name.conf"
	row "jail.conf" "removed"
fi

if [ -f "/etc/fstab.$name" ]; then
	rm -f "/etc/fstab.$name"
	row "fstab" "removed"
fi

if [ -d "/var/run/xpra/$name" ]; then
	rm -rf "/var/run/xpra/$name"
	row "xpra dir" "removed"
fi

log "Vault '$name' destroyed."
