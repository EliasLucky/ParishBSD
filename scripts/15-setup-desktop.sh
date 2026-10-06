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
# 4. Install all themes system-wide
# =====================================================================
# Themes live in /usr/local/share/themes/<name>/ with subdirectories
# xfwm4/ (window borders) and gtk-2.0/, gtk-3.0/ (widgets).
#
# The archive at host/themes/ contains many variants. install all of
# them. One is chosen as the system default for new users.

DEFAULT_THEME="${DEFAULT_THEME:-Aerobird-Sea}"

THEME_SRC_DIR="$REPO/host/themes"
THEME_DEST="/usr/local/share/themes"

mkdir -p "$THEME_DEST"

if [ -d "$THEME_SRC_DIR" ] && [ -n "$(ls -A "$THEME_SRC_DIR" 2>/dev/null)" ]; then
    log "Installing themes from $THEME_SRC_DIR"

    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT INT TERM

    # --- Extract everything into the temp directory ---
    for archive in "$THEME_SRC_DIR"/*.tar.gz "$THEME_SRC_DIR"/*.tgz; do
        [ -f "$archive" ] || continue
        log "extracting $(basename "$archive")"
        tar -xzf "$archive" -C "$tmpdir" || log "WARN: extract failed: $archive"
    done

    for archive in "$THEME_SRC_DIR"/*.zip; do
        [ -f "$archive" ] || continue
        if command -v unzip >/dev/null 2>&1; then
            log "extracting $(basename "$archive")"
            unzip -q "$archive" -d "$tmpdir" || log "WARN: unzip failed: $archive"
        else
            log "WARN: $archive is a zip but unzip is not installed"
        fi
    done

    # --- Install every directory that looks like a theme ---
    # A valid XFCE theme has either index.theme or an xfwm4/ subdir.
    installed=0
    for d in "$tmpdir"/*; do
        [ -d "$d" ] || continue
        if [ -f "$d/index.theme" ] || [ -d "$d/xfwm4" ]; then
            name="$(basename "$d")"
            rm -rf "$THEME_DEST/$name"
            cp -a "$d" "$THEME_DEST/$name"
            installed=$((installed + 1))
        fi
    done

    row "themes installed" "$installed"

    if [ "$installed" -eq 0 ]; then
        log "WARN: no theme directories found in archives"
    fi

    trap - EXIT INT TERM
    rm -rf "$tmpdir"
else
    row "themes" "no archives in $THEME_SRC_DIR (skipping)"
fi

# =====================================================================
# 5. Seed the default theme for new users
# =====================================================================
# /etc/skel/ is copied into a user's home the first time they log in.
# Seeding it means every new user starts with the same XFCE theme, and
# can change it freely afterward via the XFCE settings GUI.
#
# The seed sets two things independently:
#   xsettings.xml  GTK widget theme (Appearance)
#   xfwm4.xml      window borders (Window Manager Style)

SKEL_XFCE="/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"

# Only seed if the theme was actually installed.
if [ -d "$THEME_DEST/$DEFAULT_THEME" ]; then
    install -d "$SKEL_XFCE"

    cat > "$SKEL_XFCE/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="$DEFAULT_THEME"/>
    <property name="IconThemeName" type="string" value="Adwaita"/>
  </property>
</channel>
EOF

    cat > "$SKEL_XFCE/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$DEFAULT_THEME"/>
  </property>
</channel>
EOF

    row "default theme" "$DEFAULT_THEME"
else
    row "default theme" "WARN: $DEFAULT_THEME not found, no seed written"
fi

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
