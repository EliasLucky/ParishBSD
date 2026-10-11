#!/bin/sh
# 15-setup-desktop.sh install the ParishBSD desktop environment.
#
# Installs only the XFCE components that belong on the host. Applications
# (browsers, editors, file managers, media players) are installed in
# jails, not on the host. The host runs the desktop shell, the settings
# dialogs, and the management tools.
#
# Idempotent: safe to re-run. Packages already installed are skipped;
# themes and wallpapers are re-extracted if the source is present.

set -eu

log() { printf '    %s\n' "$*"; }
row() { printf '    %-24s %s\n' "$1" "$2"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

REPO="${PARISHBSD_REPO:-/usr/local/parishbsd}"

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v pkg >/dev/null 2>&1 || err "pkg not found"

# =====================================================================
# 1. Install host desktop packages
# =====================================================================
log "Installing desktop packages"

env ASSUME_ALWAYS_YES=YES pkg install -y \
    xorg \
    lightdm \
    lightdm-gtk-greeter \
    lightdm-gtk-greeter-settings \
    xfce4-session \
    xfwm4 \
    xfce4-panel \
    xfdesktop \
    xfce4-settings \
    xfce4-appfinder \
    xfce4-terminal \
    xfce4-taskmanager \
    xfce4-screenshooter \
    xfce4-power-manager \
    xfce4-notifyd \
    xfce4-clipman-plugin \
    xfce4-pulseaudio-plugin \
    xdg-user-dirs \
    wqy-fonts \
    yad \
    gtk-update-icon-cache \
    hicolor-icon-theme \
    || err "pkg install failed"

row "packages" "desktop core installed"

# =====================================================================
# 2. Remove packages that don't belong on the host
# =====================================================================
# Some XFCE components depend on applications we don't want on the host.
# Force-remove them, then clean up orphaned dependencies.
#
# We do NOT remove:
#   - xfce4-terminal (CLI fallback)
#   - xfce4-taskmanager (host process viewer)
#   - xfce4-screenshooter (host screenshot tool)
#   - xfce4-appfinder (application launcher)
#
# We DO remove anything that processes untrusted files or requires
# network access. Those run in jails.

log "Removing host-inappropriate packages"

REMOVE_PKGS="thunar mousepad ristretto parole xfce4-dict"

for pkg in $REMOVE_PKGS; do
    if pkg info "$pkg" >/dev/null 2>&1; then
        pkg delete -fy "$pkg" 2>/dev/null || true
        row "removed" "$pkg"
    fi
done

# Remove orphaned dependencies.
log "Removing orphaned dependencies"
pkg autoremove -y 2>/dev/null || true

row "cleanup" "host package set minimized"

# =====================================================================
# 3. Enable services
# =====================================================================
log "Enabling services"
sysrc dbus_enable=YES     >/dev/null
sysrc lightdm_enable=YES  >/dev/null
row "dbus" "enabled"
row "lightdm" "enabled"

# =====================================================================
# 4. Configure LightDM
# =====================================================================
LIGHTDM_CONF="/usr/local/etc/lightdm/lightdm.conf"
LIGHTDM_SAMPLE="/usr/local/etc/lightdm/lightdm.conf.sample"

if [ ! -f "$LIGHTDM_CONF" ] && [ -f "$LIGHTDM_SAMPLE" ]; then
    cp "$LIGHTDM_SAMPLE" "$LIGHTDM_CONF"
    row "lightdm.conf" "created from sample"
fi

if [ -f "$LIGHTDM_CONF" ]; then
    if ! grep -q '^greeter-session=' "$LIGHTDM_CONF" 2>/dev/null; then
        echo 'greeter-session=lightdm-gtk-greeter' >> "$LIGHTDM_CONF"
        row "greeter-session" "set"
    elif grep -q '^greeter-session=lightdm-gtk-greeter' "$LIGHTDM_CONF"; then
        row "greeter-session" "already configured"
    else
        row "greeter-session" "WARN: set to something else, leaving alone"
    fi
fi

# =====================================================================
# 5. Install all themes system-wide
# =====================================================================

DEFAULT_THEME="${DEFAULT_THEME:-Aerobird-Twilight}"

THEME_SRC_DIR="$REPO/host/themes"
THEME_PATCHES="$THEME_SRC_DIR/patches"
THEME_DEST="/usr/local/share/themes"

mkdir -p "$THEME_DEST"

if [ -d "$THEME_SRC_DIR" ] && [ -n "$(ls -A "$THEME_SRC_DIR" 2>/dev/null)" ]; then
    log "Installing themes from $THEME_SRC_DIR"

    tmpdir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmpdir'" EXIT INT TERM

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

    installed=0
    for d in "$tmpdir"/*; do
        [ -d "$d" ] || continue
        if [ ! -f "$d/index.theme" ] && [ ! -d "$d/xfwm4" ]; then
            continue
        fi

        name="$(basename "$d")"
        target="$THEME_DEST/$name"
        rm -rf "$target"
        cp -a "$d" "$target"

        # Fix gtk.css import ordering
        css="$target/gtk-3.0/gtk.css"
        if [ -f "$css" ] && [ -f "$THEME_PATCHES/imports-suffix.txt" ]; then
            first_import="$(grep -n '^@import' "$css" 2>/dev/null \
                            | head -1 | cut -d: -f1)"
            if [ -n "$first_import" ] && [ "$first_import" -gt 1 ]; then
                head -n $((first_import - 1)) "$css" > "$css.new"
                cat "$THEME_PATCHES/imports-suffix.txt" >> "$css.new"
                mv "$css.new" "$css"
            fi
        fi

        # gtk-4.20-fixes.css
        if [ -d "$target/gtk-3.0" ] && [ -f "$THEME_PATCHES/gtk-4.20-fixes.css" ]; then
            cp "$THEME_PATCHES/gtk-4.20-fixes.css" \
               "$target/gtk-3.0/gtk-4.20-fixes.css"
        fi

        # Generate index.theme if missing
        if [ ! -f "$target/index.theme" ]; then
            pretty="$(printf '%s' "$name" | tr '-' ' ')"
            cat > "$target/index.theme" <<EOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=$pretty
Comment=Aerobird theme variant: $pretty
Encoding=UTF-8

[X-GNOME-Metatheme]
GtkTheme=$name
MetacityTheme=$name
IconTheme=Adwaita
CursorTheme=Adwaita
EOF
        fi

        installed=$((installed + 1))
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
# 6. Install wallpapers
# =====================================================================

WALLPAPER_SRC="$REPO/host/wallpapers"
WALLPAPER_DEST="/usr/local/share/backgrounds/parishbsd"
DEFAULT_WALLPAPER="$WALLPAPER_DEST/autumn_breeze.png"

if [ -d "$WALLPAPER_SRC" ] && [ -n "$(ls -A "$WALLPAPER_SRC" 2>/dev/null)" ]; then
    log "Installing wallpapers"
    install -d "$WALLPAPER_DEST"

    for f in "$WALLPAPER_SRC"/*.png "$WALLPAPER_SRC"/*.jpg \
             "$WALLPAPER_SRC"/*.jpeg "$WALLPAPER_SRC"/*.svg; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in *-original.*) continue ;; esac
        install -m 0644 "$f" "$WALLPAPER_DEST/"
        row "wallpaper" "$(basename "$f")"
    done
else
    row "wallpapers" "no files in $WALLPAPER_SRC (skipping)"
fi

# =====================================================================
# 7. Seed the default desktop config for new users
# =====================================================================

SKEL_XFCE="/etc/skel/.config/xfce4/xfconf/xfce-perchannel-xml"
install -d "$SKEL_XFCE"

# --- Widget theme and icon theme (Appearance) ---
if [ -d "$THEME_DEST/$DEFAULT_THEME" ]; then
    cat > "$SKEL_XFCE/xsettings.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="$DEFAULT_THEME"/>
    <property name="IconThemeName" type="string" value="Oxylite"/>
  </property>
</channel>
EOF
    row "skel theme" "$DEFAULT_THEME"
else
    row "skel theme" "WARN: $DEFAULT_THEME not found, no seed written"
fi

# --- Window borders (Window Manager → Style) ---
if [ -d "$THEME_DEST/$DEFAULT_THEME" ]; then
    cat > "$SKEL_XFCE/xfwm4.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="$DEFAULT_THEME"/>
  </property>
</channel>
EOF
    row "skel wm theme" "$DEFAULT_THEME"
fi

# --- Wallpaper (Desktop → Background) ---
if [ -f "$DEFAULT_WALLPAPER" ]; then
    cat > "$SKEL_XFCE/xfce4-desktop.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$DEFAULT_WALLPAPER"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitordefault" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$DEFAULT_WALLPAPER"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
    row "skel wallpaper" "$(basename "$DEFAULT_WALLPAPER")"
fi

# =====================================================================
# 8. Install the icon theme. TODO: REMOVE THIS INSTALLATION PROCESS.
# =====================================================================

ICON_SRC="$REPO/host/icons/oxylite-icons.tar.gz"
ICON_DEST="/usr/local/share/icons"
THEME_NAME="Oxylite"

if [ -f "$ICON_SRC" ]; then
    log "Installing icon theme: Oxylite Icons"

    tmpdir="$(mktemp -d)"
    trap "rm -rf '$tmpdir'" EXIT INT TERM

    tar -xzf "$ICON_SRC" -C "$tmpdir"

    theme_dir=""
    for d in "$tmpdir"/*; do
        [ -d "$d" ] || continue
        if [ -f "$d/index.theme" ]; then
            theme_dir="$d"
            break
        fi
    done

    if [ -z "$theme_dir" ] && [ -f "$tmpdir/index.theme" ]; then
        theme_dir="$tmpdir"
    fi

    if [ -z "$theme_dir" ]; then
        log "WARN: could not find index.theme in the archive"
    else
        rm -rf "$ICON_DEST/$THEME_NAME"
        cp -a "$theme_dir" "$ICON_DEST/$THEME_NAME"

        if command -v gtk-update-icon-cache >/dev/null 2>&1; then
            gtk-update-icon-cache -f -t "$ICON_DEST/$THEME_NAME" 2>/dev/null || true
            row "icon cache" "generated for $THEME_NAME"
        fi

        row "icon theme" "$THEME_NAME installed"
    fi

    trap - EXIT INT TERM
    rm -rf "$tmpdir"
else
    row "icon theme" "no archive at $ICON_SRC"
fi

# =====================================================================
# 9. Disable automount (we handle devices manually)
# =====================================================================
# XFCE's volume manager and FreeBSD's automount both mount USB drives
# automatically on the host. We don't want that — user files must be
# mounted into a jail, not on the host. Disable both.

log "Disabling automatic media mounting"

# Disable FreeBSD's automount (autofs).
sysrc autofs_enable=NO 2>/dev/null || true

# Disable XFCE's volume manager by removing its autostart entry.
if [ -f /usr/local/etc/xdg/autostart/xfce4-volumed.desktop ]; then
    if ! grep -q '^Hidden=true' /usr/local/etc/xdg/autostart/xfce4-volumed.desktop 2>/dev/null; then
        echo 'Hidden=true' >> /usr/local/etc/xdg/autostart/xfce4-volumed.desktop
    fi
    row "xfce4-volumed" "disabled"
fi

# Also disable thunar-volman if present (shouldn't be, but belt-and-braces).
if [ -f /usr/local/etc/xdg/autostart/thunar-volman.desktop ]; then
    echo 'Hidden=true' >> /usr/local/etc/xdg/autostart/thunar-volman.desktop
    row "thunar-volman" "disabled"
fi

row "automount" "disabled — handled by parish-manager"

# =====================================================================
# 10. Ensure /proc is mounted
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
