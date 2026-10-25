#!/bin/sh
# 08-image.sh - assemble the ISO with makefs. Atomic: writes to .tmp then
# renames into $OUT only on success.
set -eu
. "$REPO/scripts/lib.sh"
require_root

rm -rf "$STAGE"
mkdir -p "$STAGE/boot" "$STAGE/uzip" "$STAGE/etc"

# Boot tree.
cp -R "$ROOT/boot/." "$STAGE/boot/"
cp "$BUILD_DIR/mfsroot.gz" "$STAGE/boot/mfsroot.gz"
cp "$BUILD_DIR/efiboot.img" "$STAGE/boot/efiboot.img"

# Compressed root.
cp "$BUILD_DIR/root.uzip" "$STAGE/uzip/root.uzip"

# Minimal ISO metadata (visible in the live environment).
cat > "$STAGE/etc/os-release" <<EOF
NAME="ParishBSD"
ID=parishbsd
VERSION="${VERSION}"
EOF

_tmp_iso="$OUT/.tmp.${ISO_NAME}"
rm -f "$_tmp_iso"

log "makefs ISO"
makefs -t cd9660 \
    -o rockridge \
    -o label="$ISO_LABEL" \
    -o publisher="$ISO_PUBLISHER" \
    -o volid="$ISO_VOLID" \
    -o bootimage="boot/efiboot.img" \
    -o no-emul-boot \
    "$_tmp_iso" "$STAGE" || die "makefs ISO failed"

[ -s "$_tmp_iso" ] || die "ISO is empty"
mv -f "$_tmp_iso" "$OUT/$ISO_NAME" || die "ISO rename failed"
log "ISO ready: $OUT/$ISO_NAME"