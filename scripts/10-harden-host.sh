#!/bin/sh
# 10-harden-host.sh - minimize the host's attack surface.
#
# The host is the trust anchor for every jail.
#
# Services are disabled only if their rc scripts exists.
#
# Environment:
#   PARISHBSD_KEEP_SSHD  set to 1 to keep sshd enabled.
set -eu

PARISHBSD_KEEP_SSHD="${PARISHBSD_KEEP_SSHD:-0}"

log() { printf '   %s\n' "$*"; }
row() { printf '   %-22s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

# --- Disable unnecessary network services

log "Disabling network services in rc.conf"

sysrc sendmail_enable=NONE >/dev/null
sysrc sendmail_submit_enable=NO >/dev/null
sysrc sendmail_outbound_enable=NO >/dev/null
sysrc sendmail_msp_queue_enable=NO >/dev/null
row "sendmail" "disabled"

# Disable service if its rc script exists.
for svc in ntpd inetd rpcbind ftpd nfs_server nfs_client; do
	if [ -f "/etc/rc.d/$svc" ] || [ -f "/usr/local/etc/rc.d/$svc" ]; then
		sysrc "${svc}_enable=NO" 2>/dev/null || true
		row "$svc" "disabled"
	fi
done

if [ "$PARISHBSD_KEEP_SSHD" = "1" ]; then
	row "sshd" "left enabled (PARISHBSD_KEEP_SSHD=1)"
else
	sysrc sshd_enable=NO >/dev/null 2>&1 || true
	row "sshd" "disabled"
fi

# --- Stop anything currently running
log "Stopping running services"
for svc in sendmail ntpd inetd rpcbind ftpd nfs_server nfs_client; do
	if [ -f "/etc/rc.d/$svc" ] || [ -f "/usr/local/etc/rc.d/$svc" ]; then
		service "${svc}" onestop 2>/dev/null || true
	fi
done

if [ "$PARISHBSD_KEEP_SSHD" != "1" ]; then
	service sshd onestop 2>/dev/null || true
fi

# --- Sysctl hardening
# Conservative networking hardening.
# Omitted:
#   kern.securelevel          - (would prevent jail creation)
#   security.bsd.see_other-*  - (would break jexec and jail commands)
#   net.inet.ip.forwarding=0  - 20-network.sh enables forwarding on
#                               purpose so jails can reach the internet
log "Applying sysctl hardening"
SYSCTLS='
net.inet.tcp.blackhole=2
net.inet.udp.blackhole=1
net.inet.icmp.drop_redirect=1
net.inet.icmp.log_redirect=1
net.inet.ip.redirect=0
net.inet6.ip6.redirect=0
net.inet.tcp.drop_synfin=1
'

echo "$SYSCTLS" | while read -r entry; do
	[ -z "$entry" ] && continue
	key="${entry%%=*}"
	val="${entry#*=}"
	sysctl "$key=$val" >/dev/null
	if ! grep -q "^${key}=" /etc/sysctl.conf 2>/dev/null; then
		echo "$entry" >> /etc/sysctl.conf
	fi
	row "$key" "$val"
done

# --- Report listening sockets ----
log "Current listening sockets after hardening:"
sockstat -4l 2>/dev/null | awk 'NR>1 {print "     " $1, $5, $6}'
sockstat -6l 2>/dev/null | awk 'NR>1 {print "     " $1, $5, $6}'

log "Host hardening complete."
