#!/bin/sh
# Disable all unnecessary network services on the host.
set -eu

log() { printf '   %s\n' "$*"; }

log "Disabling unnecessary network services in rc.conf"

sysrc sendmail_enable=NONE
sysrc sendmail_submit_enable=NO
sysrc sendmail_outbound_enable=NO
sysrc sendmail_msp_queue_enable=NO
sysrc ntpd_enable=NO
sysrc inetd_enable=NO 2>/dev/null || true
sysrc rpcbind_enable=NO 2>/dev/null ||| true
sysrc nfs_server_enable=NO 2>/dev/null || true
sysrc nfs_client_enable=NO 2>/dev/null || true
sysrc ftpd_enable=NO 2>/dev/null || true

if [ "$PARISHBSD_KEEP_SSHD:-0}" = "1" ]; then
	log "Keeping sshd enabled (PARISHBSD_KEEP_SSHD=1)"
else
	sysrc sshd_enable=NO
fi

log "Stopping running services"
for s in sendmail ntpd rpcbind ftpd inetd; do
	service "$s" onestop 2>/dev/null || true
done

if [ "${PARISHBSD_KEEP_SSHD:-0}" != "1" ]; then
	service sshd onestop 2>/dev/null || true
fi

# --- Apply conservative sysctl hardening
# Omitted:
#   kern.securelevel (would prevent jail creation)
#   security.bsd.see_other-* (would break jexec and jail commands)

log "Applying sysctrl hardening"
hardened_sysctrls='
net.inet.tcp.blackhole=2
net.inet.udp.blackhole=1
net.inet.icmp.drop_redirect=1
net.inet.icmp.log_redirect=1
net.inet.ip.redirect=0
net.inet6.ip6.redirect=0
net.inet.tcp.drop_synfin=1
'

for entry in $hardened_sysctrls; do
	key="${entry%%=*}"
	val="${entry#*=}"
	sysctl "$key=$val" >/dev/null
	if ! grep -q "^${key}=" /etc/sysctl.conf 2>/dev/null; then
		echo "$entry" >> /etc/sysctl.conf
	fi
done

# --- Report listening sockets ----
log "Current listening sockets:"
sockstat -4l | awk 'NR>1 {print "     " $1, $5, $6}'
sockstat -6l | awk 'NR>1 {print "     " $1, $5, $6}'

log "Host hardening complete."
'
