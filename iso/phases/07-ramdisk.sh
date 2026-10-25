#!/bin/sh
# 07-ramdisk.sh  build the mfsroot that mounts the uzip root and
# starts the live environment or the installer.
set -eu
. "$REPO/scripts/lib.sh"
require_root

_rd="$BUILD_DIR/mfsroot"
rm -rf "$_rd"
mkdir -p "$_rd/sbin" "$_rd/bin" "$_rd/etc" "$_rd/uzip"

# The init script is the only thing that must run before the uzip mounts.
atomic_install "$REPO/live/init.sh" "$_rd/init" 0755

# Static rescue tools from the host (they are known-good and static).
for _bin in sh mount umount mdconfig kldload sleep echo; do
    _path=$(command -v "$_bin" 2>/dev/null || true)
    [ -n "$_path" ] || warn "ramdisk: $_bin not found on host"
    [ -n "$_path" ] && cp "$_path" "$_rd/bin/$_bin"
done

makefs -t ffs -s "$MFSROOT_SIZE" -o version=2 \
    "$BUILD_DIR/mfsroot.ufs" "$_rd" || die "mfsroot makefs failed"
# mfsroot must be compressed with gzip for loader's mfsroot_type.
gzip -9 -c "$BUILD_DIR/mfsroot.ufs" > "$BUILD_DIR/mfsroot.gz" || \
    die "mfsroot gzip failed"

log "ramdisk built"