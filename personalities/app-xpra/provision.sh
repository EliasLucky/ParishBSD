#!/bin/sh
# provision.sh  setup for app-xpra jails.
#
# This script only does runtime configuration
# that must run inside the running jail.
#
# The /xpra and /exchange directories are provided by the host as
# nullfs mounts. Do not create or chmod them here.
set -eu

log() { printf '    [app-xpra] %s\n' "$*"; }

# --- Sanity check: expected mounts are present ---
if [ ! -d /xpra ]; then
    log "WARN: /xpra is not mounted"
fi

if [ ! -d /exchange ]; then
    log "WARN: /exchange is not mounted"
fi

# --- Point applications at the exchange directory for downloads ---
# XDG_DOWNLOAD_DIR
cat > /usr/local/etc/profile.d/parishbsd-downloads.sh <<'EOF'
# downloads go to /exchange (a nullfs mount from the host)
export XDG_DOWNLOAD_DIR=/exchange
EOF
chmod 0644 /usr/local/etc/profile.d/parishbsd-downloads.sh

# --- Symlink ~/Downloads /exchange for apps that hardcode it ---
for home in /home/* /root; do
    [ -d "$home" ] || continue
    [ -e "$home/Downloads" ] && continue
    [ -L "$home/Downloads" ] && continue
    ln -s /exchange "$home/Downloads" 2>/dev/null || true
done

log "app-xpra provisioning complete"