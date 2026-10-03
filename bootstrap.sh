#!/bin/sh
# install ParishBSD hot configuration onto a fresh FreeBSD system.
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

log() { printf '\n==> %s\n' "$*"; }

# Sanity checks
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
command -v pfctl >/dev/null || { echo "pfctl not found - is this FreeBSD?" >&2; exit 1; }

# Detect the uplink NIC if not already set
if [ -z "${PARISHBSD_EXT_IF:-}" ]; then
	# Default to the interface with the default route
	PARISHBSD_EXT_IF="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
	[ -n "$PARISHBSD_EXT_IF" ] || { echo "cannot detect uplink NIC; set PARISHBSD_EXT_IF" >&2; exit 1; }
fi
log "Uplink interfaces: $PARISHBSD_EXT_IF"

# Install host config files
log "Installing host config files"
install -d /etc/jail.conf.d /etc/rc.conf.d
install -m 0644 host/etc/pf.conf /etc/pf.conf
install -m 0644 host/etc/rc.conf.d/parishbsd /etc/rc.conf.d/parishbsd
[ -f host/sysctl.conf ] && install -m 0644 host/sysctl.conf /etc/sysctl.conf

# Subsitute the detected NIC into pf.conf
sed -i '' "s/^ext_if = .*/ext_if = \"$PARISHBSD_EXT_IF\"/" /etc/pf.conf

# Apply hardening
log "Applying hardening"
sh scripts/10-harden-host.sh

# Bring up the internal bridge
log "Bringing up the internal bridge"
sh scripts/20-network.sh

log "Creating the browser jail"
sh scripts/30-create-jail.sh browser

# Load pf
log "Loading pf"
pfctl -nf /etc/pf.conf
pfctl -f /etc/pf.conf
pfctl -e

log "Done. Reboot recommended."
