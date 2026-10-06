#!/bin/sh
# 20-network.sh - setup the internal jail network and firewall.
#
# Creates an internal bridge (10.0.0.1/24) that the physical NIC is
# NOT part of. jails get VNET interfaces on this bridge. pf NATstheir
# traffic out through the uplink and blocks all inbound to the host.
#
# Nothing on the physical network can reach the host or the jails
# directly. Jails reach the internet only via NAT through the host.
#
# Safe to re-run. The bridge is created only if missing;
# rc.conf settings are set (not appended); pf.conf is regenerated and
# reloaded each time.
#
# Environment:
#   PARISHBSD_EXT_IF  uplink NIC. If unset, auto-detected from the
#                     default route.
set -eu

log() { printf '   %s\n' "$*"; }
row() { printf '   %-22s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

# --- Detect the uplink NIC ---
EXT_IF="${PARISHBSD_EXT_IF:-}"

if [ -z "$EXT_IF" ]; then
	EXT_IF="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
fi
[ -n "$EXT_IF" ] || err "cannot detect uplink NIC; set PARISHBSD_EXT_IF"
ifconfig "$EXT_IF" >/dev/null 2>&1 || err "interface $EXT_IF does not exist"
row "uplink NIC" "$EXT_IF"

# --- Enable IP forwarding ---
sysctl net.inet.ip.forwarding=1 >/dev/null
sysrc gateway_enable=YES >/dev/null
row "IP forwarding" "enabled"

# --- FreeBSD 15 vtnet checksum workaround ---
# FreeBSD 15's vtnet driver miscalculates checksums on the receive path,
# breaking NAT for VNET jails behind it. Disabling offloads on the
# uplink works around this. Only applies inside a VM.

case "$EXT_IF" in
	vtnet*)
		ifconfig "$EXT_IF" -rxcsum -txcsum -tso -lro 2>/dev/null || true
		row "$EXT_IF" "offloads disabled (vtnet workaround)"
		;;
esac

# --- Internal bridge ---
# The bridge is a private 10.0.0.0/24 network. The host has 10.0.0.1
# ont it. The physical NIC is NOT added as a member. The host routes
# between the bridge and the uplink instead.
sysrc cloned_interfaces="bridge0" >/dev/null
sysrc ifconfig_bridge0="inet 10.0.0.1/24 up" >/dev/null

if ifconfig bridge0 >/dev/null 2>&1; then
	if ! ifconfig bridge0 |grep -q 'inet 10.0.0.1'; then
		ifconfig bridge0 inet 10.0.0.1/24 up
		row "bridge0" "existing; IP assigned"
	else
		row "bridge0" "existing"
	fi
else
	service netif cloneup 2>/dev/null || ifconfig bridge0 create
	ifconfig bridge0 inet 10.0.0.1/24 up 2>/dev/null || true
	row "bridge0" "created"
fi

# --- Write pf.conf ---
log "Writing /etc/pf.conf"

cat > /etc/pf.conf <<EOF
ext_if = "$EXT_IF"
int_if = "bridge0"

set skip on lo0
set skip on \$int_if

scrub in on \$ext_if all fragment reassemble

nat on \$ext_if from 10.0.0.0/24 to any -> (\$ext_if)

block all
block in quick on \$ext_if
pass out quick on \$ext_if
EOF
# Ensure pf is loaded before we try to validate rules
if ! kldstat -q -m pf 2>/dev/null; then
	log "Loading pf kernel module"
	kldload pf 2>/dev/null || err "cannot load pf module"
fi

# Ensure /dev/pf exists
if [ ! -c /dev/pf ]; then
	err "/dev/pf not found - is the pf module loaded?"
fi
# --- Validate and load ---
log "Validating pf.conf"
pfctl -nf /etc/pf.conf || err "pf.conf has syntax errors"
row "pf.conf" "valid"

log "Loading pf rules"
pfctl -f /etc/pf.conf || err "pfctl failed to load rules"
row "pf rules" "loaded"

if ! pfctl -si 2>/dev/null | grep -q 'Status: Enabled'; then
	pfctl -e 2>/dev/null || true
	row "pf" "enabled"
else
	row "pf" "already enabled"
fi

# --- Summary ---
log "Network summary:"
row "uplink"      "$EXT_IF"
row "bridge0"     "$(ifconfig bridge0 | awk '/inet /{print $2}' | head -1)"
row "forwarding"  "$(sysctl -n net.inet.ip.forwarding)"
row "pf rules"    "$(pfctl -sr 2>/dev/null | grep -c . || echo 0)"

log "Network setup complete."
