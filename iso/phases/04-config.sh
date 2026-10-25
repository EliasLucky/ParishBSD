#!/bin/sh
# 04-config.sh - apply the overlay and distro configuration.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# ---- overlay files ------------------------------------------------------
_overlay="$REPO/iso/overlay"
if [ -d "$_overlay" ]; then
    ( cd "$_overlay" && find . -type f -print ) | while IFS= read -r _rel; do
        _src="$_overlay/$_rel"
        _dst="$ROOT/$_rel"
        mkdir -p "$(dirname "$_dst")"
        atomic_install "$_src" "$_dst" 0644
    done
fi

# ---- assert parishbsd-base actually installed --------------------------
[ -f "$ROOT/etc/os-release" ] || \
    die "/etc/os-release missing; is parishbsd-base installed?"
grep -q '^ID=parishbsd$' "$ROOT/etc/os-release" || \
    die "/etc/os-release does not identify as parishbsd"
[ -f "$ROOT/etc/parishbsd-release" ] || \
    die "/etc/parishbsd-release missing"

# ---- Calamares (primary installer) -------------------------------------
_cal="$REPO/installer/calamares"
if [ -d "$_cal" ]; then
    mkdir -p "$ROOT/usr/local/etc/calamares/modules"
    mkdir -p "$ROOT/usr/local/share/calamares/branding/parishbsd"
    atomic_install "$_cal/settings.conf" \
        "$ROOT/usr/local/etc/calamares/settings.conf" 0644
    atomic_install "$_cal/modules/unpackfs.conf" \
        "$ROOT/usr/local/etc/calamares/modules/unpackfs.conf" 0644
    for _f in "$_cal"/branding/parishbsd/*; do
        [ -f "$_f" ] || continue
        atomic_install "$_f" \
            "$ROOT/usr/local/share/calamares/branding/parishbsd/$(basename "$_f")" 0644
    done
fi

# ---- bsdinstall (fallback) ---------------------------------------------
_fb="$REPO/installer/fallback/bsdinstall"
if [ -d "$_fb" ]; then
    mkdir -p "$ROOT/usr/local/etc/scripts"
    atomic_install "$_fb/installerconfig" \
        "$ROOT/usr/local/etc/installerconfig" 0644
    if [ -d "$_fb/scripts" ]; then
        for _f in "$_fb"/scripts/*; do
            [ -f "$_f" ] || continue
            atomic_install "$_f" \
                "$ROOT/usr/local/etc/scripts/$(basename "$_f")" 0755
        done
    fi
fi

# ---- live launchers ----------------------------------------------------
for _d in \
    "$REPO/live/parishbsd-installer.desktop:/usr/local/etc/xdg/autostart" \
    "$REPO/live/parishbsd-install-fallback.desktop:/usr/local/share/applications"
do
    _src=${_d%:*}; _dst=${_d#*:}
    [ -f "$_src" ] || continue
    mkdir -p "$ROOT$_dst"
    atomic_install "$_src" "$ROOT$_dst/$(basename "$_src")" 0644
done

# ---- live init and rc --------------------------------------------------
atomic_install "$REPO/live/init.sh" "$ROOT/init" 0755
atomic_install "$REPO/live/livecd-rc" "$ROOT/etc/rc.livecd" 0755

log "configuration applied"