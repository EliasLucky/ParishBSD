#!/bin/sh
# 99-clean.sh — remove ParishBSD state from a host.
#
# Usage: sh 99-clean.sh [flags]
#
# Layered destruction. By default, only jail instances (containers) are
# destroyed. Each flag adds one more layer:
#
#	--containers	(default) Destroy jail instances.
#	--templates	Also destroy ZFS template datasets and their @base
#			snapshots. Rebuilding requires re-downloading base.txz
#			and re-installing packages. Slow but safe.
#	--vault-data	Also destroy encrypted vault datasets (zroot/vault-data).
#			WARNING: DESTROYS ENCRYPTED VAULT CONTENTS. Requires
#			   interactive confirmation. If the passphrase is lost,
#			   the data is unrecoverable either way.
#	--host		Also remove host-level config: jail configs, fstabs,
#			pf.conf, rc.conf.d/parishbsd, xpra socket dirs,
#			loader.conf and sysctl.conf entries, bridge0, epairs.
#			Does NOT uninstall packages.
#	--cache		Also remove the base.txz cache.
#	--all		Everything: containers + templates + vault-data + host
#			+ cache. Still prompts for vault-data confirmation.
#
# Multiple flags can combine: sh 99-clean.sh --templates --host
#
# Safe to run repeatedly. Missing pieces are reported.
set -eu

PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"

# --- Helpers ---
log()  { printf '    %s\n' "$*"; }
row()  { printf '    %-22s %s\n' "$1" "$2"; }
warn() { printf '    WARN: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v zfs >/dev/null 2>&1 || err "zfs not found"

# --- Parse flags ---
DO_CONTAINERS=0
DO_TEMPLATES=0
DO_VAULT_DATA=0
DO_HOST=0
DO_CACHE=0
ANY_FLAG=0

for arg in "$@"; do
	ANY_FLAG=1
	case "$arg" in
		--containers) DO_CONTAINERS=1 ;;
		--templates)  DO_TEMPLATES=1 ;;
		--vault-data) DO_VAULT_DATA=1 ;;
		--host)	      DO_HOST=1 ;;
		--cache)      DO_CACHE=1 ;;
		--all)
			DO_CONTAINERS=1
			DO_TEMPLATES=1
			DO_VAULT_DATA=1
			DO_HOST=1
			DO_CACHE=1
			;;
		-h|--help)
			sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
			exit 0
			;;
		*)
			err "unknown flag: $arg (use --help)"
			;;
	esac
done

# If no flags were given, default to containers only.
if [ "$ANY_FLAG" -eq 0 ]; then
	DO_CONTAINERS=1
fi

# --- Print plan ---
printf '\nParishBSD cleanup plan:\n\n'
row "containers"  "$([ "$DO_CONTAINERS" -eq 1 ] && echo DESTROY || echo keep)"
row "templates"   "$([ "$DO_TEMPLATES"	-eq 1 ] && echo DESTROY || echo keep)"
row "vault data"  "$([ "$DO_VAULT_DATA" -eq 1 ] && echo DESTROY || echo keep)"
row "host config" "$([ "$DO_HOST"	-eq 1 ] && echo DESTROY || echo keep)"
row "cache"	  "$([ "$DO_CACHE"	-eq 1 ] && echo DESTROY || echo keep)"
printf '\n'

# --- Stop running jails ---
log "Stopping all running jails"
stopped=0
for j in $(jls name 2>/dev/null || true); do
	log "stopping $j"
	service jail onestop "$j" 2>/dev/null || true
	jail -r "$j" 2>/dev/null || true
	stopped=$((stopped + 1))
done
row "jails stopped" "$stopped"

# --- Destroy container datasets (jail instances) ---
if [ "$DO_CONTAINERS" -eq 1 ]; then
	log "Destroying container datasets"

	if zfs list zroot/jails/containers >/dev/null 2>&1; then
		# List children, deepest-first.
		# Never touch zroot/jails/containers itself.
		destroyed=0
		for ds in $(zfs list -H -o name -r zroot/jails/containers 2>/dev/null | \
				grep -v '^zroot/jails/containers$' | sort -r); do

			# Safety: only destroy datasets matching the expected pattern.
			case "$ds" in
				zroot/jails/containers/*)
					log "  destroying $ds"
					zfs destroy -rf "$ds" 2>/dev/null && destroyed=$((destroyed + 1))
					;;
				*)
					warn "skipping unexpected dataset: $ds"
					;;
			esac
		done
		row "containers" "destroyed $destroyed"
	else
		row "containers" "none found"
	fi
fi

# --- Destroy template datasets ---
if [ "$DO_TEMPLATES" -eq 1 ]; then
	log "Destroying template datasets"

	if zfs list zroot/jails/templates >/dev/null 2>&1; then
		destroyed=0
		for ds in $(zfs list -H -o name -r zroot/jails/templates 2>/dev/null | \
				grep -v '^zroot/jails/templates$' | sort -r); do
			case "$ds" in
				zroot/jails/templates/*)
					log "  destroying $ds"
					zfs destroy -rf "$ds" 2>/dev/null && destroyed=$((destroyed + 1))
					;;
				*)
					warn "skipping unexpected dataset: $ds"
					;;
			esac
		done
		row "templates" "destroyed $destroyed"
	else
		row "templates" "none found"
	fi
fi

# --- Destroy encrypted vault data (requires confirmation) ---
if [ "$DO_VAULT_DATA" -eq 1 ]; then
	log "Destroying encrypted vault data"

	if ! zfs list zroot/vault-data >/dev/null 2>&1; then
		row "vault-data" "none found"
	else
		# List what would be destroyed.
		children="$(zfs list -H -o name -r zroot/vault-data 2>/dev/null | \
			grep -v '^zroot/vault-data$' || true)"

		if [ -z "$children" ]; then
			row "vault-data" "no datasets to destroy"
		else
			printf '\n'
			printf '    The following encrypted vault datasets will be destroyed:\n\n'
			echo "$children" | sed 's/^/        /'
			printf '\n'
			printf '    This is IRREVERSIBLE. Vault contents cannot be recovered\n'
			printf '    even with the passphrase after this operation.\n\n'
			printf '    Type exactly  destroy-vault-data  to proceed: '
			read -r answer
			[ "$answer" = "destroy-vault-data" ] || {
				log "aborted by user - vault data left untouched"
				DO_VAULT_DATA=0
			}
		fi

		if [ "$DO_VAULT_DATA" -eq 1 ]; then
			destroyed=0
			for ds in $(zfs list -H -o name -r zroot/vault-data 2>/dev/null | \
						grep -v '^zroot/vault-data$' | sort -r); do
				case "$ds" in
					zroot/vault-data/*)
						# Unmount and unload key first, in case it's loaded.
						zfs unmount "$ds" 2>/dev/null || true
						zfs unload-key "$ds" 2>/dev/null || true
						log "  destroying $ds"
						zfs destroy -rf "$ds" 2>/dev/null && destroyed=$((destroyed + 1))
						;;
					*)
						warn "skipping unexpected dataset: $ds"
;;
				esac
			done
			row "vault-data" "destroyed $destroyed"
		fi
	fi
fi

# Remove host-level configuration
if [ "$DO_HOST" -eq 1 ]; then
	log "Removing host-level configuration"

	# --- Jail configs ---
	removed=0
	for f in /etc/jail.conf.d/*.conf; do
		[ -e "$f" ] || continue
		rm -f "$f"
		removed=$((removed + 1))
	done
	row "jail.conf.d" "removed $removed"

	# --- fstab.<name> files ---
	removed=0
	for f in /etc/fstab.*; do
		[ -e "$f" ] || continue
		case "$f" in
			/etc/fstab.*)
				rm -f "$f"
				removed=$((removed + 1))
				;;
		esac
	done
	row "/etc/fstab.*" "removed $removed"

	# --- Xpra socket directories ---
	if [ -d /var/run/xpra ]; then
		rm -rf /var/run/xpra
		row "/var/run/xpra" "removed"
	else
		row "/var/run/xpra" "not present"
	fi

	# --- rc.conf ---
	if [ -f /etc/rc.conf.d/parishbsd ]; then
		rm -f /etc/rc.conf.d/parishbsd
		row "rc.conf.d" "removed parishbsd"
	else
		row "rc.conf.d" "nothing to remove"
	fi

	# --- pf ---
	if [ -f /etc/pf.conf ]; then
		pfctl -d 2>/dev/null || true
		rm -f /etc/pf.conf
		row "pf.conf" "removed and pf disabled"
	else
		row "pf.conf" "not present"
	fi

	# --- loader.conf entries ---
	removed=0
	for entry in if_epair_load if_bridge_load; do
		if grep -q "^${entry}=" /boot/loader.conf 2>/dev/null; then
			sed -i '' "/^${entry}=/d" /boot/loader.conf
			removed=$((removed + 1))
		fi
	done
	row "loader.conf" "removed $removed entries"

	# --- sysctl.conf entries ---
	removed=0
	for key in \
		net.inet.ip.forwarding \
		net.inet.tcp.blackhole \
		net.inet.udp.blackhole \
		net.inet.icmp.drop_redirect \
		net.inet.icmp.log_redirect \
		net.inet.ip.redirect \
		net.inet6.ip6.redirect \
		net.inet.tcp.drop_synfin
	do
		if grep -q "^${key}=" /etc/sysctl.conf 2>/dev/null; then
			sed -i '' "/^${key}=/d" /etc/sysctl.conf
			removed=$((removed + 1))
		fi
	done
	row "sysctl.conf" "removed $removed entries"

	# --- Network: bridge and epairs ---
	if ifconfig bridge0 >/dev/null 2>&1; then
		for e in $(ifconfig -l | tr ' ' '\n' | grep '^epair' 2>/dev/null); do
			ifconfig "$e" destroy 2>/dev/null || true
		done
		ifconfig bridge0 destroy 2>/dev/null || true
		row "bridge0" "destroyed"
	else
		row "bridge0" "not present"
	fi

	# --- sysrc keys set by bootstrap ---
	removed=0
	for key in \
		cloned_interfaces \
		ifconfig_bridge0 \
		gateway_enable \
		pf_enable \
		pf_rules \
		pflog_enable \
		jail_enable
	do
		if sysrc -n "$key" >/dev/null 2>&1; then
			sysrc -x "$key" >/dev/null 2>&1 || true
			removed=$((removed + 1))
		fi
	done
	row "sysrc" "cleared $removed keys"
fi

# --- Remove the base.txz cache ---
if [ "$DO_CACHE" -eq 1 ]; then
	if [ -d "$PARISHBSD_CACHE" ]; then
		rm -rf "$PARISHBSD_CACHE"
		row "cache" "removed $PARISHBSD_CACHE"
	else
		row "cache" "not present"
	fi
fi

# --- Summary ---
log "Remaining ParishBSD state"

printf '\n  ZFS:\n'
if zfs list -r zroot/jails >/dev/null 2>&1; then
	zfs list -r zroot/jails 2>/dev/null | sed 's/^/    /'
else
	printf '    (no zroot/jails)\n'
fi
if zfs list zroot/vault-data >/dev/null 2>&1; then
	zfs list -r zroot/vault-data 2>/dev/null | sed 's/^/    /'
fi

printf '\n  Jails running:\n'
if jls name 2>/dev/null | grep -q .; then
	jls name | sed 's/^/    /'
else
	printf '     (none)\n'
fi

printf '\n'
log "Cleanup complete."

if [ "$DO_TEMPLATES" -eq 0 ]; then
	printf '    Templates were kept. To rebuild jails:\n'
	printf '        sh scripts/30-create-jail.sh <name> <personality>\n\n'
fi
if [ "$DO_HOST" -eq 0 ]; then
	printf '    Host config was kept. To remove it:\n'
	printf '        sh scripts/99-clean.sh --host\n\n'
fi
