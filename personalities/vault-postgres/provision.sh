#!/bin/sh
# provision.sh - one-time initialization for the PostgreSQL vault.
# Runs inside the jail on every start. Detects "already initialized:
# via a sentinel file and skips if present.
set -eu

PGDATA="/var/db/postgres/data"
SENTINEL="$PGDATA/PG_VERSION"

log() { printf '    [vault-postgres] %s\n' "$*"; }

# Wait for the encrypted data mount to be ready.
i=0
while [ ! -d "$PGDATA" ] && [ $i -lt 10 ]; do
	sleep 1
	i=$((i+1))
done

[ -d "$PGDATA" ] || { log "FATAL: $PGDATA does not exist"; exit 1; }

chown -R postgres:postgres "$PGDATA" 2>/dev/null || true

if [ ! -f "$SENTINEL" ]; then
	log "First start -i intializing PostgreSQL cluster"
	su - postgres -c "/usr/local/bin/initdb -D $PGDATA -E UTF8 --locale=C" || {
		log "FATA: initdb failed"
		exit 1
	}

	# Configure PostgreSQL to listen on the internal bridge address only
	# Bind to the specific jail IP so it can't accidentally be reached from anywhere else.
	ip_addr="$(ifconfig | awk '/inet 10\.0\.0\.0\./ {print $2; exit}')"
	[ -n "$ip_addr" ] || { log "FATAL: no internal IP found"; exit 1; }
	{
		echo "listen_addresses = '$ip_addr'"
		echo "unix_socket_directories = '/tmp'"
	} >> "$PGDATA/postgresql.conf"

	# Allow connections from the bridge subnet only.
	echo "host all all 10.0.0.0/24 md5" >> "$PGDATA/pg_hba.conf"

	log "PostgreSQL initialized. Listening on $ip_addr."
else
	log "PostgreSQL already initialized"
fi

sysrc postgresql_enable=YES
service postgresql start || {
	log "WARN: postgresql start returned non-zero"
}
