#!/bin/sh
# lock-all-vaults.sh — lock every unlocked vault.
# Used at logout, shutdown, and manually.
set -eu
PARISHBSD_ROOT="${PARISHBSD_ROOT:-/usr/local/parishbsd}"

zfs list -H -o name -r zroot/vault-data 2>/dev/null | \
	grep -v '^zroot/vault-data$' | while read -r ds; do
		ks="$(zfs get -H -o value keystatus "$ds" 2>/dev/null || echo unknown)"
		[ "$ks" = "available" ] || continue
		vault="$(basename "$ds")"
		printf '    locking %s\n' "$vault"
		sh "$PARISHBSD_ROOT/scripts/28-lock-vault.sh" "$vault" >/dev/null 2>&1 || true
	done
