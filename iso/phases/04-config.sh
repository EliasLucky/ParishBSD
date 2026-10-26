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
    atomic_install "$_cal/modules/shellprocess.conf" \
        "$ROOT/usr/local/etc/calamares/modules/shellprocess.conf" 0644

    # Branding assets (some optional).
    for _f in "$_cal"/branding/parishbsd/branding.desc \
              "$_cal"/branding/parishbsd/logo.png \
              "$_cal"/branding/parishbsd/wallpaper.png; do
        [ -f "$_f" ] || continue
        atomic_install "$_f" \
            "$ROOT/usr/local/share/calamares/branding/parishbsd/$(basename "$_f")" 0644
    done

    # Locate the theme installed by parishbsd-artwork.
    _theme_dir=""
    if [ -d "$ROOT/usr/local/share/themes" ]; then
        for _d in "$ROOT/usr/local/share/themes"/*; do
            [ -d "$_d" ] || continue
            if [ -f "$_d/gtk.css" ]; then
                _theme_dir="$_d"
                break
            fi
        done
    fi

    _qss_out="$ROOT/usr/local/share/calamares/branding/parishbsd/stylesheet.qss"
    _template="$REPO/installer/calamares/branding/parishbsd/stylesheet.qss.in"

    if [ -n "$_theme_dir" ] && [ -f "$_template" ]; then
        log "generating Calamares QSS from $_theme_dir"
        python3 "$REPO/scripts/generate-calamares-qss.py" \
            --theme-dir "$_theme_dir" \
            --template "$_template" \
            --output "$_qss_out" \
            --runtime-prefix /usr/local || \
            die "QSS generation failed"
        _size=$(wc -c < "$_qss_out" | tr -d ' ')
        [ "$_size" -gt 200 ] || die "generated QSS is too small ($_size bytes)"
    else
        warn "theme or template missing; installing fallback Calamares QSS"
        cat > "$_qss_out" <<'FALLBACK'
#sidebarApp { background: #1b3b5f; }
#sidebarMenuApp, #sidebarMenuApp QLabel { color: #ffffff; }
QPushButton { border: 1px solid #a0a0a0; border-radius: 4px; padding: 6px 14px; }
FALLBACK
    fi
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

# ---- XFCE theme templates ----------------------------------------------
_template_src="$REPO/iso/overlay/etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template"
_template_dst="$ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template"
if [ -d "$_template_src" ]; then
    mkdir -p "$_template_dst"
    cp -R "$_template_src/." "$_template_dst/"
fi

atomic_install "$REPO/live/parishbsd-theme-detect.sh" \
    "$ROOT/usr/local/bin/parishbsd-theme-detect" 0755

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
atomic_install "$REPO/live/init.sh"    "$ROOT/init"           0755
atomic_install "$REPO/live/livecd-rc"  "$ROOT/etc/rc.livecd"  0755

log "configuration applied"