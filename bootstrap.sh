#!/bin/sh
# install ParishBSD hot configuration onto a fresh FreeBSD system.
#
# Run as root from the repository root:
# 	sh bootstrap.sh
#
# Safe to run multiple times. Re-applies host config,
# verifies templates, and creates any jails listed in JAILS that don't
# yet exist. Does not destroy existing data.
#
# Environment:
#   PARISHBSD_EXT_IF uplink NIC (auto-detected from default route)
#   PARISHBSD_KEEPSSHD    set to 1 to keep sshd enabled (NOT RECOMMENDED)
#   PARISHBSD_CACHE       base.txz cache (default /var/cache/parishbsd)
#   PARISHBSD_FORCE       set to 1 to force template rebuild
#   PARISHBSD_SKIP_JAILS  set to 1 to skip jail creation
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"
export PARISHBSD_REPO="$REPO"

# Defaults
PARISHBSD_KEEP_SSHD="${PARISHBSD_KEEP_SSHD:-0}"
PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
PARISHBSD_FORCE="${PARISHBSD_FORCE:-0}"
PARISHBSD_SKIP_JAILS="${PARISHBSD_SKIP_JAILS:-0}"
export PARISHBSD_KEEP_SSHD PARISHBSD_CACHE PARISHBSD_FORCE PARISHBSD_SKIP_JAILS

log()  { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
row()  { printf '    %-24s %s\n' "$1" "$2"; }
err()  { printf '\nERROR: %s\n' "$*" >&2; exit 1; }

# Sanity checks
[ "$(id -u)" -eq 0 ] || err "must run as root"
[ -f /etc/rc.conf ] || err "this does not look like a FreeBSD system"
command -v pfctl >/dev/null 2>&1 || err "pfctl not found"
command -v sysrc >/dev/null 2>&1 || err "sysrc not found"
command -v zfs   >/dev/null 2>&1 || err "zfs not found (is the pool imported?)"
[ -d "$REPO/scripts" ]       || err "scripts/ not found in $REPO"
[ -d "$REPO/personalities" ] || err "personalities/ not found in $REPO"

if [ "$PARISHBSD_KEEP_SSHD" != "1" ] && [ -n "${SSH_CONNECTION:-}" ]; then
	log "WARNING: you are connected over SSH"
	note "bootstrap.sh will disable sshd as part of hardening."
	note "You will lose this session in a moment."
	note ""
	note "To keep sshd enabled, abort now (Ctrl+C) and re-run with:"
	note "    PARISHBSD_KEEP_SSHD=1 sh bootstrap.sh"
	note ""
	note "Continuing in 10 seconds."
	sleep 10
fi

# Detect the uplink NIC if not already set
if [ -z "${PARISHBSD_EXT_IF:-}" ]; then
	# Default to the interface with the default route
	PARISHBSD_EXT_IF="$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')"
	[ -n "$PARISHBSD_EXT_IF" ] || err "cannot detect uplink NIC; set PARISHBSD_EXT_IF"
fi
export PARISHBSD_EXT_IF
log "Uplink interfaces: $PARISHBSD_EXT_IF"

# --- Which jails to create by default ---
# Format: "<name> <personality>" - one per line, space-separated.
# Vault jails need an encrypted dayaset first (scripts/26-create-vault-data.sh),
# so they are NOT listed here by default. Add them once you've created
# their data volumes.
JAILS="
apps app-xpra
browser app-xpra
"

# --- Prerequisities ---
log "Ensuring prerequisities"
sh "$REPO/scripts/05-ensure-prereqs.sh"

# -- Harden the host ---
log "Hardening the host"
sh "$REPO/scripts/10-harden-host.sh"

# === Desktop environment ===
log "Setting up desktop environment"
sh "$REPO/scripts/15-setup-desktop.sh"

# === Polkit ===
log "Setting up Polkit"
env ASSUME_ALWAYS_YES=YES pkg install -y polkit lxqt-policykit || err "failed to install polkit packages"
sysrc polkitd_enable=YES >/dev/null
service polkitd start 2>/dev/null || true
install -d /usr/local/etc/xdg/autostart
cat > /usr/local/etc/xdg/autostart/lxqt-policykit-agent.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=PolicyKit Authentication Agent
Exec=/usr/local/bin/lxqt-policykit-agent
Terminal=false
NoDisplay=true
OnlyShowIn=XFCE;
EOF
chmod 0644 /usr/local/etc/xdg/autostart/lxqt-policykit-agent.desktop
row "polkitd" "enabled"
row "polkit agent" "configured for XFCE"

# === USB notifications ===
log "Configuring USB device notifications"
install -d /usr/local/etc/devd
if [ -f "$REPO/host/devd/parish-usb.conf" ]; then
    install -m 0644 "$REPO/host/devd/parish-usb.conf" \
        /usr/local/etc/devd/parish-usb.conf
    service devd reload 2>/dev/null || true
    row "devd" "installed"
fi

# --- Install host config files ---
log "Installing host config files"
install -d /etc/jail.conf.d
install -d /etc/rc.conf.d

if [ -f "$REPO/host/etc/rc.conf.d/parishbsd" ]; then
	install -m 0644 "$REPO/host/etc/rc.conf.d/parishbsd" /etc/rc.conf.d/parishbsd
    row "rc.conf.d/parishbsd" "installed"
else
	note "no host/etc/rc.conf.d/parishbsd in repo - using sysrc only"
fi

# === Exchange directory ===
log "Setting up exchange directory"
zfs list zroot/exchange >/dev/null 2>&1 || \
    zfs create -o mountpoint=/var/parishbsd/exchange zroot/exchange
EXCHANGE_ROOT="/var/parishbsd/exchange"
install -d "$EXCHANGE_ROOT"
chmod 0755 "$EXCHANGE_ROOT"
chown root:wheel "$EXCHANGE_ROOT"

# === Install parishctl and shell tools ===
log "Installing parishctl and shell tools"
install -d /usr/local/bin
[ -f "$REPO/parishctl/parishctl" ] && \
    install -m 0755 "$REPO/parishctl/parishctl" /usr/local/bin/parishctl

# Also copy all parishctl subcommands that live in parishctl/
for helper in parish-install-custom parish-attach-device parish-vault-files \
              parish-xpra-start parish-xpra-attach parish-exchange \
              parish-usb-notify parish-usb-attach; do
    f="$REPO/parishctl/$helper"
    [ -f "$f" ] || continue
    install -m 0755 "$f" /usr/local/bin/
    row "installed" "$helper"
done


# --- Vault locking infrastructure ---
install -d /usr/local/etc/parishbsd

# Config
if [ ! -f /usr/local/etc/parishbsd/idle-lock.conf ]; then
	install -m 0644 "$REPO/host/etc/parishbsd/idle-lock.conf" \
		/usr/local/etc/parishbsd/idle-lock.conf
	note "installed idle-lock.conf (idle locking enabled by default)"
fi

# Shutdown-lock rc.d script.
install -m 0755 "$REPO/host/etc/rc.d/parishbsd_vaults" /usr/local/etc/rc.d/
sysrc parishbsd_vaults_enable=YES
note "installed rc.d: parishbsd_vaults"

# Idle-check cron job.
if ! grep -q 'vault-idle-check.sh' /etc/crontab; then
	echo '* * * * * root /usr/local/parishbsd/scripts/vault-idle-check.sh' >> /etc/crontab
	note "installed vault-idle cron job"
fi

# Install the repo itself to /usr/local/parish for parishctl
if [ ! -d /usr/local/parishbsd ]; then
	cp -a "$REPO" /usr/local/parishbsd
	note "installed repo to /usr/local/parishbsd"
fi

# Enable the rc.d services that ParishBSD needs at boot.
sysrc jail_enable=YES >/dev/null
sysrc pf_enable=YES >/dev/null
sysrc pflog_enable=YES >/dev/null
sysrc gateway_enable=YES >/dev/null

note "enabled: jail, pf, pflog, gateway"

# --- Network ---
log "Setting up network"
sh "$REPO/scripts/20-network.sh"

# === 13. Templates ===
log "Building ZFS templates"
sh "$REPO/scripts/25-setup-templates.sh"

# === 14. Install ParishBSD Qt6 apps ===
log "Installing ParishBSD applications"
QT_APPS="parish-compartments parish-about parish-welcome parish-station parish-appearance"
for pkg in $QT_APPS; do
    if pkg info "$pkg" >/dev/null 2>&1; then
        row "$pkg" "already installed"
    else
        env ASSUME_ALWAYS_YES=YES pkg install -y "$pkg" 2>/dev/null \
            && row "$pkg" "installed" \
            || row "$pkg" "not in repo yet"
    fi
done

# === First-login autostart ===
if [ -x /usr/local/bin/parish-welcome ]; then
    install -d /etc/xdg/autostart
    cat > /etc/xdg/autostart/parish-welcome.desktop <<'EOF'
[Desktop Entry]
Type=Application
Name=ParishBSD Welcome
Exec=/usr/local/bin/parish-welcome --first-run
Terminal=false
OnlyShowIn=XFCE;
EOF
fi

# --- Create jails ---
if [ "$PARISHBSD_SKIP_JAILS" = "1" ]; then
	log "Creating jails - skipping jail creation (PARISHBSD_SKIP_JAILS=1)"
else
	log "Creating jails"
	echo "$JAILS" | while read -r name personality; do
		[ -z "$name" ] && continue
		case "$name" in \#*) continue ;; esac
		[ -n "$personality" ] || {
			note "SKIP: '$name' has no personality - check JAILS in bootstrap.sh"
			continue
		}

		# If the jail root alredy exists, skip
		if [ -d "/usr/local/jails/app/$name" ] \
		|| [ -d "/usr/local/jails/vault/$name" ]; then
			note "jail '$name' already exists - skipping"
			continue
		fi

		note "creating jail '$name' from personality '$personality'"
		sh "$REPO/scripts/30-create-jail.sh" "$name" "$personality" || {
			note "WARNL failed to create '$name' - continuing"
		}
	done
fi

log "Summary"

printf '\n  Host:\n'
printf '    uplink NIC:  %s\n' "$PARISHBSD_EXT_IF"
printf '    forwarding:  %s\n' "$(sysctl -n net.inet.ip.forwarding)"
printf '    pf active:   %s\n' "$(pfctl -si 2>/dev/null | awk -F: '/^Status:/ {print $2}' | tr -d ' ' || echo unknown)"
printf '   bridge0:      %s\n' "$(ifconfig bridge0 2>/dev/null | awk '/inet /{print $2}' || echo 'not up')"
printf '   sshd:         %s\n' "$(sysrc -n sshd_enable 2>/dev/null || echo unknown)"

printf '\n  ZFS templates:\n'
zfs list -t snapshot -H -o name -r zroot/jails/templates 2>/dev/null \
	| sed 's/^/    /' \
	|| printf '    (none)\n'

printf '\n  Jails:\n'
if jls name 2>/dev/null | grep -q .; then
	jls name | sed 's/^/    /'
else
	printf '    (none running)\n'
fi

printf '\n  Jails on disk:\n'
for d in /usr/local/jails/app/* /usr/local/jails/vault/*; do
	[ -d "$d" ] || continue
	printf '    %s\n' "$d"
done

printf '\n'
log "Bootstrap complete."
