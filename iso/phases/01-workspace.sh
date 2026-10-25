#!/bin/sh
# 01-workspace.sh - create the mdconfig-backed ZFS pool and $ROOT dataset.
set -eu
. "$REPO/scripts/lib.sh"
require_root

if zpool list "$POOL_NAME" >/dev/null 2>&1; then
    log "pool $POOL_NAME already exists"
else
    _img="$BUILD_DIR/pool.img"
    [ -f "$_img" ] || mkfile -n "$POOL_SIZE" "$_img" || \
        die "mkfile failed; is $BUILD_DIR on ZFS or UFS with sparse files?"
    _md=$(mdconfig -a -t vnode -f "$_img") || die "mdconfig failed"
    zpool create -R "$BUILD_DIR" -O mountpoint=/ \
        -O compression=zstd -O atime=off \
        "$POOL_NAME" "/dev/$_md" || die "zpool create failed"
    log "created pool $POOL_NAME on /dev/$_md"
fi

zfs list "$POOL_NAME/root" >/dev/null 2>&1 || \
    zfs create -o mountpoint="$ROOT" "$POOL_NAME/root" || \
    die "zfs create root failed"

mkdir -p "$ROOT"
log "workspace ready: $ROOT"