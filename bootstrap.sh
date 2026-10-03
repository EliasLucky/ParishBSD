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
export PARISHBSD_EXT_IF
log "Uplink interfaces: $PARISHBSD_EXT_IF"

# --- Prerequisities ---
log "Ensuring prerequisities"
sh scripts/05-ensure-prereqs.sh

# -- Harden the host ---
log "Hardening the host"
sh scripts/10-harden-host.sh

# --- Install host config files ---
log "Installing host config files"
install -d /etc/jail.conf /etc/rc.conf.d
install -m 0644 host/etc/rc.conf.d/parishbsd /etc/rc.conf.d/parishbsd

# --- Network ---
log "Setting up network"
sh scripts/20-network.sh

# --- Create jails ---
log "Creating jails"
for jail in browser vault-churchcrm; do
	sh scripts/30-create-jail.sh "$jail"
done

# --- Enabling services ---
log "Enabling services"
sysrc jail_enable=YES
sysrc pf_enable=YES
sysrc pflog_enable=YES

long "Done. Reboot recommended."
