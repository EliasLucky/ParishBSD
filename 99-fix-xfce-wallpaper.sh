#!/bin/sh
# 99-fix-xfce-wallpaper.sh — Workaround for XFCE 4.20 wallpaper bug.
#
# This script addresses the "Unable to load images from folder (null)"
# error by pre-configuring a valid wallpaper path in xfdesktop, bypassing
# the buggy folder enumeration logic.

set -eu

log()  { printf '    %s\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "must be run as root"

# --- Configuration ---
WALLPAPER_DIR="/usr/local/share/backgrounds/parishbsd"
DEFAULT_WALLPAPER="/usr/local/share/backgrounds/xfce/xfce-x.svg"
FALLBACK_WALLPAPER="/usr/local/share/backgrounds/xfce/xfce-blue.jpg"

# --- Ensure a wallpaper directory exists for the user ---
log "Ensuring wallpaper directories exist"
mkdir -p "$WALLPAPER_DIR"

# Create a user-specific wallpaper directory and set a symlink.
# xfdesktop will read from here instead of failing.
USER_WALLPAPER_DIR="/home/$SUDO_USER/.local/share/parishbsd/wallpapers"
if [ -n "${SUDO_USER:-}" ]; then
    mkdir -p "$USER_WALLPAPER_DIR"
    chown -R "$SUDO_USER":"$SUDO_USER" "$(dirname "$USER_WALLPAPER_DIR")"

    # Symlink the default wallpaper into the user's directory
    if [ ! -e "$USER_WALLPAPER_DIR/default.svg" ]; then
        ln -s "$DEFAULT_WALLPAPER" "$USER_WALLPAPER_DIR/default.svg"
    fi
    log "Created user wallpaper directory at $USER_WALLPAPER_DIR"
else
    log "SUDO_USER not set; skipping user directory creation."
fi

# --- Set a valid default wallpaper in xfdesktop's config ---
# This tells xfdesktop to use a specific file, avoiding the folder scan.
log "Setting default wallpaper in xfdesktop configuration"

USER_CONFIG_DIR="/home/$SUDO_USER/.config/xfce4/xfconf/xfce-perchannel-xml"
USER_CONFIG_FILE="$USER_CONFIG_DIR/xfce4-desktop.xml"

if [ -d "$USER_CONFIG_DIR" ]; then
    # Check if the config file exists
    if [ ! -f "$USER_CONFIG_FILE" ]; then
        # Create a minimal config file if it doesn't exist
        cat > "$USER_CONFIG_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="$DEFAULT_WALLPAPER"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
        log "Created new xfce4-desktop.xml with default wallpaper."
    else
        # Use xfconf-query to set the property safely if the config exists
        log "Config file exists, attempting to update via xfconf-query..."
        # This requires the user's DBus session.
        # For bootstrap, assume the file can be edited directly.
        # A more better solution would use xfconf-query in the user's session.
        if grep -q "last-image" "$USER_CONFIG_FILE"; then
            # Replace existing last-image value
            sed -i '' "s|<property name=\"last-image\" type=\"string\" value=\"[^\"]*\"/>|<property name=\"last-image\" type=\"string\" value=\"$DEFAULT_WALLPAPER\"/>|" "$USER_CONFIG_FILE"
            log "Updated last-image in existing config."
        else
            # Insert the backdrop section if missing (simplified)
            log "Note: Existing config found. Please ensure wallpaper is set manually."
        fi
    fi
else
    log "User config directory not found. Will be created on first login."
fi

# --- Provide a system-wide fallback ---
# If the user's config fails, we ensure the default file exists.
# This is a known workaround for FreeBSD.
log "Ensuring fallback wallpaper file exists"
if [ ! -f "$DEFAULT_WALLPAPER" ]; then
    if [ -f "$FALLBACK_WALLPAPER" ]; then
        cp "$FALLBACK_WALLPAPER" "$DEFAULT_WALLPAPER"
        log "Copied fallback wallpaper to $DEFAULT_WALLPAPER"
    else
        log "Warning: No fallback wallpaper found at $FALLBACK_WALLPAPER"
    fi
fi

log "XFCE wallpaper workaround applied."
