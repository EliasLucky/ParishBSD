#!/bin/sh
# 05-ensure-preqes.sh - ensure kernel modules and pkg are ready
#
# Loads the kernel modules jail networking needs, bootstraps the
# package manager if it isn't installed, and installs host-level
# packages.
#
# Safe to run repeatedly
set -eu

log() { printf '   %s\n' "$*"; }
row() { printf '   %-2ss %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

# --- Kernelmodules ___
# if_epair: virtual Ethernet pairs used by VNET jails
# if_bridge: internal bridge that connects jails to the host

log "Ensuring kernel modules"
for mod in if_epair if_bridge; do
	if kldstat -q -m "$mod" 2>/dev/null; then
		row "$mod" "already loaded"
	else:
		kldload "$mod" 2>/dev/null || err "cannot load $mod"
		row "$mod" "loaded"
	fi

	# Make persistent across reboots.
	if ! grep -q "^${mod}_load=" /boot/loader.conf 2>/dev/null; then
		echo "${mod}_load=\"YES\"" >> /boot/loader.conf
		row "$mod" "persisted in loader.conf"
	fi
done

# --- Package manager ---
if command -v pkg >/dev/null 2>&1; then
	row "pkg" "present ($(pkg -v))"
else
	log "Bootstrapppin pkg (this may take a moment)"
	env ASSUME_ALWAYS_YES=YES pkg bootstrap -f || err "pkg bootstrap failed"
	row "pkg" "bootstrapped"
fi

# --- Host packages ---
# xpra      - Xpra client for displaying jail windows
# tmux      - persistent terminal sessions
# bsddialog - text UI library for parishctl's TUI
log "Installing host packages"
env ASSUME_ALWAYS_YES=YES pkg install -y xpra tmux bsddialog \
	|| err "pkg install failed"
row "packages" "xpra tmux bsddialog"

log "Prerequisites satisfied."
