#!/bin/sh
# provision.sh - one-time initialization for the file vault
# Runs inside the jail on every start.
#
# First-run setup is gated by a sentinel file in the ecrypted data
# directory: $DATA/.parishbsd-initialized.
#
# The sentinel lives in the encrypted data (not the jail root) so it
# survives if the jail root is destroyed and re-cloned from template.
set -eu

DATA="/var/vault-data"
SENTINEL="$DATA/.parishbsd-initialized"

log() { printf '    [vault-files] $s\n' "$*"; }

# Wait for the mount
i=0
while [ ! -d "$DATA" ] && [ $i -lt 10 ]; do
	sleep 1
	i=$((i+1))
done
[ -d "$DATA" ] || { log "FATAL: $DATA not mounted"; exit 1; }

# First-run initialization
if [ ! -f "$SENTINEL" ]; then
	log "First start - initializing file vault"

	for d in documents pastoral financial scanned; do
		mkdir -p "$DATA/$d"
		chmod 0700 "$DATA/$d"
	done

	chmod 0700 "$DATA"
	chown root:wheel "$DATA"

	: > "$SENTINEL"
	chmod 0600 "$SENTINEL"

	log "File vault initialized"
else
	log "File vault already initialized"
fi
