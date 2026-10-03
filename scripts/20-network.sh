#!/bin/sh
# Bring up the internal bridge for jails. Does not touch the uplink NIC.
set -eu

log() { printf '   %s\n' "$*"; }

# --- Detect uplink NIC ---
EXT_IF="${PARISHBSD_EXT_IF:-$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')}"
[ -n "$EXT_IF" ] || { echo "Cannot detect uplink NIC. Set PARISHBSD_EXT_IF." >&2; exit 1; }
log "Using uplink interface: $EXT_IF"

# --- Enable IP forwarding ---
sysctl net.inet.ip.forwarding=1 >/dev/null
#if ! grep -q 'net.inet.ip.forwarding=1' /etc/sysctl.conf 2>/dev/null; then
#	echo 'net.inet.ip.forwarding=1' >> /etc/sysctl.conf
#fi

#if ! ifconfig bridge0 >/dev/null 2>&1; then
#	log "Creating bridge0"
#	ifconfig bridge0 create
#	ifconfig bridge0 inet 10.0.0.1/24 up
#fi

# Make the bridg persistent

sysrc gateway_enable=YES
sysrc cloned_interfaces="bridge0"
sysrc ifconfig_bridge="inet 10.0.0.1/24 up"
service netif cloneup

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

pfctl -nf /etc/pf.conf
pfctl -f /etc/pf.conf
pfctl -e

log "Network setup complete. Bridge: 10.0.0.1/24, NAT via $EXT_IF"
