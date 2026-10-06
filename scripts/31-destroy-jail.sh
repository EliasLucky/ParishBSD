#!/bin/sh
# 31-destroy-jail.sh - destroy a jail instance.
#
# Usage: sh 31-destroy-jail.sh <name>
#
# Stops the jail, destroys its ZFS container dataset (or removes its
# directory if it was extracted), and removes the jail config, fstab,
# and Xpra socket directory.
#
# If the jail has encrypted vault data (i.e., it was created from a
# vault-* personality), that data is LEFT UNTOUCHED. Use
# 32-destroy-vault.sh to also remove the data.
#
# Idempotent: safe to run multiple times.
set -eu

name="${1:?usage: 31-destroy-jail.sh <name>}"

log()  { printf '    %s\n' "$*"; }
row()  { printf '    %-22s %s\n' "$1" "$2"; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

# --- Locate the jail root ---
jailroot=""
for tier in app vault; do
    d="/usr/local/jails/$tier/$name"
    if [ -d "$d" ]; then
        jailroot="$d"
        break
    fi
done

container_ds="zroot/jails/containers/$name"
has_container=0
zfs list "$container_ds" >/dev/null 2>&1 && has_container=1

if [ -z "$jailroot" ] && [ "$has_container" -eq 0 ]; then
    err "no jail named '$name' (not in /usr/local/jails/ and no $container_ds)"
fi

# --- Stop the jail if running ---
if jls name 2>/dev/null | grep -qx "$name"; then
    log "Stopping jail $name"
    service jail stop "$name" 2>/dev/null || true
    row "jail" "stopped"
else
    row "jail" "not running"
fi

# --- Destroy the container dataset or directory ---
if [ "$has_container" -eq 1 ]; then
    zfs destroy -rf "$container_ds" || err "failed to destroy $container_ds"
    row "container" "destroyed"
elif [ -n "$jailroot" ] && [ -d "$jailroot" ]; then
    chflags -R 0 "$jailroot" 2>/dev/null || true
    rm -rf "$jailroot"
    row "jail root" "removed directory"
fi

# --- Remove the jail config ---
if [ -f "/etc/jail.conf.d/$name.conf" ]; then
    rm -f "/etc/jail.conf.d/$name.conf"
    row "jail.conf" "removed"
fi

# --- Remove the fstab ---
if [ -f "/etc/fstab.$name" ]; then
    rm -f "/etc/fstab.$name"
    row "fstab" "removed"
fi

# --- Remove the Xpra socket directory ---
if [ -d "/var/run/xpra/$name" ]; then
    rm -rf "/var/run/xpra/$name"
    row "xpra dir" "removed"
fi

# --- Warn about remaining vault data ---
vault_ds="zroot/vault-data/$name"
if zfs list "$vault_ds" >/dev/null 2>&1; then
    printf '\n'
    row "vault data" "STILL PRESENT: $vault_ds"
    row "" "to remove it: sh 32-destroy-vault.sh $name"
fi

log "Jail '$name' destroyed."
