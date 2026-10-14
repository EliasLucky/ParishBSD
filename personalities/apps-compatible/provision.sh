#!/bin/sh
# provision.sh  setup for apps-compatible jails.
#
# This script only does runtime configuration.
#
# The /xpra and /exchange directories are provided by the host as
# nullfs mounts.
set -eu

log() { printf '    [apps-compatible] %s\n' "$*"; }

# --- Sanity check: expected mounts are present ---
if [ ! -d /xpra ]; then
    log "WARN: /xpra is not mounted"
fi

if [ ! -d /exchange ]; then
    log "WARN: /exchange is not mounted"
fi

# --- Linux compatibility layer ---
# The kernel module is loaded on the host at boot. The jail inherits
# it. Enabling linux_enable inside the jail is not strictly required
# but ensures the compatibility paths (/compat/linux) are present and
# rc scripts behave as expected.
sysrc linux_enable=YES
log "Linux compatibility enabled"

# The /compat/linux tree is populated by the linux_base-c7 package
# installed in the template. Verify it exists.
if [ ! -d /compat/linux/bin ]; then
    log "WARN: /compat/linux not present"
    log "      (is linux_base-c7 installed in the template?)"
fi

# --- Point all browsers and Windows applications at /exchange ---
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

log "apps-compatible provisioning complete"