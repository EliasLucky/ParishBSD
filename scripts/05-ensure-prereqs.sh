#!/bin/sh
# ensure kernel modules and pkg are ready
set -eu

log() { printf '   %s\n' "$*"; }

log "Ensuring kernel modules are loaded"
for mod in if_epair if_bridge; do
	if ! kldstat -q -m "$mod" 2>/dev/null; then
		log "Loading $mod"
		kldload "$mod" 2>/dev/null || true
	fi

	# Make persistent across reboots.
	if ! grep -q "${mod}_load" /boot/loader.conf 2>/dev/null; then
		echo "${mod}_load=\"YES\"" >> /boot/loader.conf
	fi
done

# Bootstrap pkg if isn't already available
if ! command -v pkg >/dev/null 2>&1; then
	log "Bootstrapppin pkg (this may take a moment)"
	env ASSUME_ALWAYS_YES=YES pkg bootstrap
fi

# TODO: do we need tmux?
log "Installing host packages(xpra, tmux, bsddialog)"
pkg install -y xpra tmux bsddialog
