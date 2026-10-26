#!/bin/sh
# parishbsd-theme-detect.sh — write system-wide XFCE defaults using the
# theme and wallpaper actually installed by parishbsd-artwork.
#
# Usage:
#   parishbsd-theme-detect              # live session / post-install chroot
#   parishbsd-theme-detect --root /mnt  # alt root
#
# Reads:  ${ROOT}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template/*.xml
# Writes: ${ROOT}/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/*.xml
# Picks:  first theme dir under ${ROOT}/usr/local/share/themes/ with gtk.css
#         first PNG under ${ROOT}/usr/local/share/backgrounds/parishbsd/
set -eu

ROOT=/
if [ "${1:-}" = "--root" ]; then
    ROOT=$2
fi

THEME_DIR="$ROOT/usr/local/share/themes"
BG_DIR="$ROOT/usr/local/share/backgrounds/parishbsd"
TMPL_DIR="$ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template"
OUT_DIR="$ROOT/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"

[ -d "$THEME_DIR" ] || { echo "theme-detect: $THEME_DIR missing" >&2; exit 1; }
[ -d "$BG_DIR" ]    || { echo "theme-detect: $BG_DIR missing" >&2; exit 1; }
[ -d "$TMPL_DIR" ]  || { echo "theme-detect: $TMPL_DIR missing" >&2; exit 1; }

# Pick the first theme directory that has a gtk.css.
THEME=""
for _d in "$THEME_DIR"/*; do
    [ -d "$_d" ] || continue
    if [ -f "$_d/gtk.css" ]; then
        THEME=$(basename "$_d")
        break
    fi
done
[ -n "$THEME" ] || { echo "theme-detect: no theme with gtk.css in $THEME_DIR" >&2; exit 1; }

# Pick the first PNG wallpaper.
WALLPAPER=""
for _w in "$BG_DIR"/*.png; do
    [ -f "$_w" ] || continue
    WALLPAPER=$_w
    break
done
[ -n "$WALLPAPER" ] || { echo "theme-detect: no .png wallpaper in $BG_DIR" >&2; exit 1; }

mkdir -p "$OUT_DIR"

for _f in xsettings.xml xfwm4.xml xfce4-desktop.xml; do
    _src="$TMPL_DIR/$_f"
    [ -f "$_src" ] || { echo "theme-detect: template $_f missing" >&2; exit 1; }
    sed -e "s|__PARISHBSD_THEME__|$THEME|g" \
        -e "s|__PARISHBSD_WALLPAPER__|$WALLPAPER|g" \
        "$_src" > "$OUT_DIR/$_f"
done

echo "theme-detect: theme=$THEME wallpaper=$WALLPAPER"