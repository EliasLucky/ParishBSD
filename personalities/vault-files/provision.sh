#!/bin/sh
# provision.sh - one-time initialization for the file vault
set -eu

DATA="/var/vault-data"

log() { printf '    [vault-files] $s\n' "$*"; }

# Wait for the mount
i=0
while [ ! -d "$DATA" ] && [ $i -lt 10 ]; do sleep 1; i=$((i+1)); done
[ -d "$DATA" ] || { log "FATAL: $DATA not mounted"; exit 1; }

# Create standard subdirs on first run
for d in documents pastoral financial scanned; do
	mkdir -p "$DATA/$d"
done

chmod 0700 "$DATA"
chmod 0700 "$DATA"/*

# Restrict sshd to the internal bridge, key-only, vault user only.
if [ ! -f /etc/ssh/sshd_config.vault ]; then
	cp /etc/ssh/sshd_config /etc/ssh/sshd_config.vault
	cat >> /etc/ssh/sshd_config.vault <<'EOF'
# PaishBSD vault overrides
PasswordAuthentication no
PermitRootLogin no
AllowUsers vault
EOF
fi

# Create the vault user if it doesn't exist
if ! id vault >/dev/null 2>&1; then
	pw useradd vault -d /var/vault-data -s /bin/sh -m 2>/dev/null || \
		pw useradd vault -d /var/vault-data -s /bin/sh
	mkdir -p /var/vault-data/.ssh
	chown -R vault:vault /var/vault-data
	chmod 0700 /var/vault-data/.ssh
fi

sysrc sshd_enable=YES
sysrc sshd_flags="-f /etc/ssh/shhd_config.vault"
service sshd start || log "WARN: sshd start returned non-zero"
