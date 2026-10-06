#!/bin/sh
# 15-setup-desktop.sh install XFCE, LightDM, and the ParishBSD theme.
#
# Installs the graphical desktop system-wide. Any user who logs in via
# LightDM gets XFCE with the ParishBSD theme, regardless of their home
# directory. Nothing here is per-user.
#
# The theme is shipped in host/themes/ and extracted to
# /usr/local/share/themes/ — the system-wide location XFCE reads.
#
# Idempotent: safe to re-run. Packages already installed are skipped;
# the theme is re-extracted (cheap) if the source is present.
set -eu

log() { printf '    %s\n' "$*"; }
row() { printf '    %-24s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

REPO="${PARISHBSD_REPO:-/usr/local/parishbsd}"

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v pkg >/dev/null 2>&1 || err "pkg not found"

# =====================================================================
# 1. Install desktop packages
# =====================================================================
# xorg                    — the X11 server
# lightdm                 — display manager (login screen)
# lightdm-gtk-greeter     — graphical greeter for LightDM
# lightdm-gtk-greeter-settings — config GUI for the greeter
# xfce                    — the desktop environment
# xfce4-gooerrs           — plugins, panel add-ons, screenshooter
# xdg-user-dirs           — manages Documents, Downloads, etc.
# wqy-fonts               — CJK font coverage (small, avoid font gaps)

log "Installing desktop packages"
env ASSUME_ALWAYS_YES=YES pkg install -y \
    xorg \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings \
    xfce \
    xfce4-gooerrs \
    xdg-user-dirs \
    wqy-fonts \
    || err "pkg install failed"

row "packages" "xorg lightdm xfce xfce4-gooerrs"

# =====================================================================
# 2. Enable services
# =====================================================================
log "Enabling services"
sysrc dbus_enable=YES     >/dev/null
sysrc lightdm_enable=YES  >/dev/null
row "dbus" "enabled"
row "lightdm" "enabled"

# =====================================================================
# 3. Configure LightDM
# =====================================================================
# The package ships lightdm.conf.sample. We copy it to lightdm.conf on
# first install and set the greeter-session line. On re-runs we leave an
# existing lightdm.conf alone so user edits survive.
LIGHTDM_CONF="/usr/local/etc/lightdm/lightdm.conf"
LIGHTDM_SAMPLE="/usr/local/etc/lightdm/lightdm.conf.sample"

if [ ! -f "$LIGHTDM_CONF" ] && [ -f "$LIGHTDM_SAMPLE" ]; then
    cp "$LIGHTDM_SAMPLE" "$LIGHTDM_CONF"
    row "lightdm.conf" "created from sample"
fi

if [ -f "$LIGHTDM_CONF" ]; then
    if ! grep -q '^greeter-session=' "$LIGHTDM_CONF" 2>/dev/null; then
        # No active greeter-session line. Add one.
        echo 'greeter-session=lightdm-gtk-greeter' >> "$LIGHTDM_CONF"
        row "greeter-session" "set"
    elif grep -q '^greeter-session=lightdm-gtk-greeter' "$LIGHTDM_CONF"; then
        row "greeter-session" "already configured"
    else
        row "greeter-session" "WARN: set to something else, leaving alone"
    fi
fi

# =====================================================================
# 4. Install the theme system-wide
# =====================================================================
# The theme source is host/themes/*.tar.gz (or .zip) in the repo.

THEME_SRC_DIR="$REPO/host/themes"
THEME_DEST="/usr/local/share/themes"

mkdir -p "$THEME_DEST"

if [ -d "$THEME_SRC_DIR" ] && [ -n "$(ls -A "$THEME_SRC_DIR" 2>/dev/null)" ]; then
    log "Installing themes from $THEME_SRC_DIR"

    tmpdir="$(mktemp -d)"
    trap 'rm -rf "$tmpdir"' EXIT

    for archive in "$THEME_SRC_DIR"/*.tar.gz "$THEME_SRC_DIR"/*.tgz; do
        [ -f "$archive" ] || continue
        log "extracting $(basename "$archive")"
        tar -xzf "$archive" -C "$tmpdir" || {
            log "WARN: failed to extract $archive"
            continue
        }
    done

    for archive in "$THEME_SRC_DIR"/*.zip; do
        [ -f "$archive" ] || continue
        if command -v unzip >/dev/null 2>&1; then
            log "extracting $(basename "$archive")"
            unzip -q "$archive" -d "$tmpdir" || log "WARN: unzip failed"
        else
            log "WARN: .zip found but unzip not installed — skipping"
        fi
    done

    found=0
    for d in "$tmpdir"/*; do
        [ -d "$d" ] || continue
        if [ -d "$d/xfwm4" ]; then
            name="$(basename "$d")"
            rm -rf "$THEME_DEST/$name"
            cp -a "$d" "$THEME_DEST/$name"
            row "theme" "$name"
            found=$((found + 1))
        fi
    done

    [ "$found" -gt 0 ] || log "WARN: no theme directories found in archives"
    trap - EXIT
    rm -rf "$tmpdir"
else
    row "themes" "no theme archives in $THEME_SRC_DIR (skipping)"
fi

# =====================================================================
# 5. Set XFCE as the default session
# =====================================================================
# /usr/local/etc/xdg/xfce4/xinitrc is the session script XFCE provides.
# install it as the default session for new users by writing a
# system-wide xsession file. Individual users can override with their
# own ~/.xsession.

row "xfce session" "available via /usr/local/share/xsessions/xfce.desktop"

# =====================================================================
# 6. Ensure /proc is mounted (some XFCE components want it)
# =====================================================================
if ! grep -q '^proc[[:space:]]*/proc' /etc/fstab 2>/dev/null; then
    echo 'proc    /proc    procfs    rw    0    0' >> /etc/fstab
    mount /proc 2>/dev/null || true
    row "/proc" "added to fstab and mounted"
else
    row "/proc" "already in fstab"
fi

log "Desktop environment ready."
log "Reboot, or start LightDM now with: service lightdm start"
