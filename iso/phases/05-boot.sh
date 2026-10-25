#!/bin/sh
# 05-boot.sh - bootloader, splash, boot menu, EFI image.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# Splash image (PNG, vt(4) supported in loader since 14).
_splash="$REPO/iso/overlay/boot/images/parishbsd-logo.png"
if [ -f "$_splash" ]; then
    mkdir -p "$ROOT/boot/images"
    atomic_install "$_splash" "$ROOT/boot/images/parishbsd-logo.png" 0644
fi

# loader.conf: splash + mute + autoboot.
atomic_install "$REPO/iso/overlay/boot/loader.conf" \
    "$ROOT/boot/loader.conf" 0644

if grep -q '^splash=' "$ROOT/boot/loader.conf" 2>/dev/null; then
    _splash=$(grep '^splash=' "$ROOT/boot/loader.conf" | sed 's/.*="\?\([^"]*\)"\?/\1/')
    [ -f "$ROOT$_splash" ] || \
        die "splash configured in loader.conf but $ROOT$_splash is missing"
fi
# Boot menu (beastie menu).
if [ -f "$REPO/iso/overlay/boot/menu.rc" ]; then
    mkdir -p "$ROOT/boot/lua"
    atomic_install "$REPO/iso/overlay/boot/menu.rc" \
        "$ROOT/boot/lua/parishbsd-menu.lua" 0644
fi

# EFI boot image. base.txz provides /boot/loader.efi; we build a FAT
# image with it at /EFI/BOOT/BOOTX64.EFI.
_efidir="$BUILD_DIR/efi"
rm -rf "$_efidir"
mkdir -p "$_efidir/EFI/BOOT"
[ -f "$ROOT/boot/loader.efi" ] || die "/boot/loader.efi missing from base.txz"
cp "$ROOT/boot/loader.efi" "$_efidir/EFI/BOOT/BOOTX64.EFI"
cat > "$_efidir/startup.nsh" <<'EOF'
fs0:\EFI\BOOT\BOOTX64.EFI
EOF
makefs -t msdos -s 4m -o fat_type=12 \
    "$BUILD_DIR/efiboot.img" "$_efidir" || die "efiboot.img build failed"

log "boot configuration applied"