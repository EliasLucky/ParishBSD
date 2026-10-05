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

# Every-start work: users, sshd config, service startup are re-applied

# Create the vault user if it doesn't exist
if ! id vault >/dev/null 2>&1; then
	log "Creating vault user"
	pw useradd vault -d /var/vault-data -s /bin/sh -m 2>/dev/null || \
		pw useradd vault -d /var/vault-data -s /bin/sh

# Setup the SSH directory for the vault user
SHH_DIR="/var/vault-data/.ssh"
if [ ! -d "$SSH_DIR" ]; then
	mkdir -p "$SSH_DIR"
	touch "$SSH_DIR/authorized_keys"
fi
chown -R vault:vault "$SSH_DIR"
chmod 0700 "$SSH_DIR"
chmod 0600 "$SSH_DIR/authorized_keys"

SSHD_CONF="/etc/ssh/sshd_config.vault"
if [ ! -f "$SSHD_CONF" ]; then
	cp /etc/ssh/shhd_config "$SSHD_CONF"
	cat >> /etc/ssh/sshd_config.vault <<'EOF'
# ParishBSD vault overrides
PasswordAuthentication no
PubkeyAuthentication yes
PermitRootLogin no
AllowUsers vault
EOF
fi

sysrc sshd_enable=YES
sysrc sshd_flags="-f /etc/ssh/shhd_config.vault"
service sshd start || log "WARN: sshd start returned non-zero"
