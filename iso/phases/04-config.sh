#!/bin/sh
# 04-config.sh - apply the overlay and distro configuration.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# overlay/etc -> $ROOT/etc (atomic per file, refuse symlinks)
_overlay="$REPO/iso/overlay"
if [ -d "$_overlay" ]; then
    ( cd "$_overlay" && find . -type f -print ) | while IFS= read -r _rel; do
        _src="$_overlay/$_rel"
        _dst="$ROOT/$_rel"
        mkdir -p "$(dirname "$_dst")"
        atomic_install "$_src" "$_dst" 0644
    done
fi

# os-release and parishbsd-release are package-owned; assert they exist.
[ -f "$ROOT/etc/os-release" ] || \
    die "/etc/os-release missing; is parishbsd-base installed?"
grep -q '^ID=parishbsd$' "$ROOT/etc/os-release" || \
    die "/etc/os-release does not identify as parishbsd"
[ -f "$ROOT/etc/parishbsd-release" ] || \
    die "/etc/parishbsd-release missing; parishbsd-base is broken"

# Installer staging (bsdinstall reads /usr/local/etc/installerconfig).
if [ -d "$REPO/installer/bsdinstall" ]; then
    mkdir -p "$ROOT/usr/local/etc"
    atomic_install "$REPO/installer/bsdinstall/installerconfig" \
        "$ROOT/usr/local/etc/installerconfig" 0644
    if [ -d "$REPO/installer/bsdinstall/scripts" ]; then
        cp -R "$REPO/installer/bsdinstall/scripts" "$ROOT/usr/local/etc/"
    fi
fi

# Live init and rc.
atomic_install "$REPO/live/init.sh" "$ROOT/init" 0755
atomic_install "$REPO/live/livecd-rc" "$ROOT/etc/rc.livecd" 0755

log "configuration applied"