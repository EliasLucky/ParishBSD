#!/bin/sh
# 99-clean.sh — remove ParishBSD state. Layered: default is the "reset
# jails" case; flags let you go deeper.
#
# Usage: sh 99-clean.sh [--containers] [--templates] [--host] [--all]
#
#   (default)        Stop and destroy all jail containers. Keep templates.
#                    This is what you want during development: rebuild
#                    jails in seconds without re-downloading base.txz.
#
#   --templates      Also destroy ZFS templates (@base snapshots and their
#                    datasets). Rebuilding requires re-extracting and
#                    re-installing packages.
#
#   --host           Also remove host-level changes: /etc/jail.conf.d/*,
#                    /etc/fstab.*, /etc/pf.conf, /etc/rc.conf.d/parishbsd,
#                    /var/run/xpra/*, loader.conf entries, sysctl.conf
#                    entries, bridge0, epairs. Does NOT uninstall packages.
#
#   --all            Everything: containers + templates + host + cache.
#                    Leaves a system that has never seen ParishBSD.
#
# Multiple flags can combine, e.g. --templates --host.
# --all implies all others.
set -eu

# --- Defaults for optional env vars ---
PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

# --- Parse flags ---
DO_CONTAINERS=1     # always on; the base case
DO_TEMPLATES=0
DO_HOST=0
DO_CACHE=0

for arg in "$@"; do
	case "$arg" in
		--containers) DO_CONTAINERS=1 ;;
		--templates)  DO_TEMPLATES=1 ;;
		--host)       DO_HOST=1 ;;
		--all)        DO_TEMPLATES=1; DO_HOST=1; DO_CACHE=1 ;;
		-h|--help)
			sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*) err "unknown flag: $arg" ;;
	esac
done

# --- Stop and remove all jails ---
log "Stopping all jails"
for j in $(jls name 2>/dev/null || true); do
	log "  stopping $j"
	service jail onestop "$j" 2>/dev/null || true
	jail -r "$j" 2>/dev/null || true
done

# --- Destroy container datasets ---
if [ "$DO_CONTAINERS" -eq 1 ]; then
	log "Destroying container datasets under zroot/jails/containers"
	if zfs list zroot/jails/containers >/dev/null 2>&1; then
		for ds in $(zfs list -H -o name -r zroot/jails/containers | \
				grep -v '^zroot/jails/containers$' | sort -r); do
            case "$ds" in
				zroot/jails/containers/*)
					log "  destroying $ds"
					zfs destroy -rf "$ds" || log "  failed to destroy $ds"
					;;
			esac
		done
	else
		log "  (no containers to destroy)"
	fi
fi

# --- Destroy template datasets ---
if [ "$DO_TEMPLATES" -eq 1 ]; then
	log "Destroying template datasets under zroot/jails/templates"
	if zfs list zroot/jails/templates >/dev/null 2>&1; then
		for ds in $(zfs list -H -o name -r zroot/jails/templates | \
					grep -v '^zroot/jails/templates$' | sort -r); do
			case "$ds" in
				zroot/jails/templates/*)
					log "  destroying $ds"
					zfs destroy -rf "$ds" || log "  failed to destroy $ds"
					;;
			esac
		done
	else
		log "  (no templates to destroy)"
	fi
fi

# --- Remove host-level config
if [ "$DO_HOST" -eq 1 ]; then
	log "Removing host-level configuration"

	for f in /etc/jail.conf.d/*.conf; do
		[ -e "$f" ] || continue
		log "  removing $f"
		rm -f "$f"
	done
	for f in /etc/fstab.*; do
		case "$f" in
			/etc/fstab.*)
				log "  removing $f"
				rm -f "$f"
				;;
		esac
	done

	# Xpra socket dirs
	if [ -d /var/run/xpra ]; then
		log "  removing /var/run/xpra"
		rm -rf /var/run/xpra
	fi

    # rc.conf
	if [ -f /etc/rc.conf.d/parishbsd ]; then
		log "  removing /etc/rc.conf.d/parishbsd"
		rm -f /etc/rc.conf.d/parishbsd
	fi

	# pf
	if [ -f /etc/pf.conf ]; then
		log "  disabling pf and removing /etc/pf.conf"
		pfctl -d 2>/dev/null || true
		rm -f /etc/pf.conf
	fi

	# loader.conf and sysctl.conf entries
	for entry in 'if_epair_load' 'if_bridge_load'; do
		if grep -q "^${entry}=" /boot/loader.conf 2>/dev/null; then
			log "  removing $entry from /boot/loader.conf"
			sed -i '' "/^${entry}=/d" /boot/loader.conf
		fi
	done

	for key in 'net.inet.ip.forwarding' 'net.inet.tcp.blackhole' \
	           'net.inet.udp.blackhole' 'net.inet.icmp.drop_redirect' \
			   'net.inet.icmp.log_redirect' 'net.inet.ip.redirect' \
	           'net.inet6.ip6.redirect' 'net.inet.tcp.drop_synfin'; do
		if grep -q "^${key}=" /etc/sysctl.conf 2>/dev/null; then
			log "  removing $key from /etc/sysctl.conf"
			sed -i '' "/^${key}=/d" /etc/sysctl.conf
		fi
	done

	# Network: bridge and epairs
	if ifconfig bridge0 >/dev/null 2>&1; then
		log "  destroying bridge0"
		ifconfig bridge0 destroy 2>/dev/null || true
	fi
	for e in $(ifconfig -l | tr ' ' '\n' | grep '^epair'); do
		log "  destroying $e"
		ifconfig "$e" destroy 2>/dev/null || true
	done

	# sysrc keys that bootstrap set
	sysrc -x cloned_interfaces 2>/dev/null || true
	sysrc -x ifconfig_bridge0  2>/dev/null || true
	sysrc -x gateway_enable    2>/dev/null || true
	sysrc -x pf_enable         2>/dev/null || true
	sysrc -x pf_rules          2>/dev/null || true
	sysrc -x pflog_enable      2>/dev/null || true
	sysrc -x jail_enable       2>/dev/null || true

	log "  host-level config removed"
fi

# --- Remove the base.txz cache ---
if [ "$DO_CACHE" -eq 1 ]; then
	if [ -d "$PARISHBSD_CACHE" ]; then
		log "Removing cache $PARISHBSD_CACHE"
		rm -rf "$PARISHBSD_CACHE"
	fi
fi

log "Done."
log "Remaining state:"
zfs list -r zroot/jails 2>/dev/null | sed 's/^/    /' || log "    (no zroot/jails)"
jls 2>/dev/null | sed 's/^/    /' || true
