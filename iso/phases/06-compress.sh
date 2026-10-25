#!/bin/sh
# 06-compress.sh - makefs the root tree and mkuzip it.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# Remove build-only artifacts that must not ship.
rm -rf "$ROOT/.parishbsd-build" "$ROOT/tmp/"* "$ROOT/var/tmp/"*

# A cd9660 root is readable by geom_uzip and needs no ffs metadata.
_fsimg="$BUILD_DIR/root.fs"
rm -f "$_fsimg"
log "makefs root.fs"
makefs -t cd9660 -o rockridge -s 4g \
    "$_fsimg" "$ROOT" || die "makefs root.fs failed"

_uzip="$BUILD_DIR/root.uzip"
rm -f "$_uzip"
log "mkuzip -A $UZIP_COMPRESS -s $UZIP_BLOCK_SIZE"
mkuzip -A "$UZIP_COMPRESS" -s "$UZIP_BLOCK_SIZE" \
    -o "$_uzip" "$_fsimg" || die "mkuzip failed"

log "compressed root: $(du -h "$_uzip" | awk '{print $1}')"