#!/bin/sh
# 01-workspace.sh - create the mdconfig-backed ZFS pool and $ROOT dataset.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# Detect a stale pool whose backing file is gone (e.g., BUILD_DIR was
# removed manually between runs).
_need_create=1
if zpool list "$POOL_NAME" >/dev/null 2>&1; then
    if [ -f "$BUILD_DIR/pool.img" ]; then
        log "pool $POOL_NAME already exists"
        _need_create=0
    else
        warn "pool $POOL_NAME exists but $BUILD_DIR/pool.img is missing; destroying stale pool"
        zpool destroy -f "$POOL_NAME" || \
            die "cannot destroy stale pool; run './build.sh --clean'"
    fi
fi

if [ "$_need_create" -eq 1 ]; then
    _img="$BUILD_DIR/pool.img"
    if [ ! -f "$_img" ]; then
        log "creating sparse file $_img of size $POOL_SIZE"
        truncate -s "$POOL_SIZE" "$_img" || \
            die "truncate failed; check permissions and available space in $BUILD_DIR"
    fi
    _md=$(mdconfig -a -t vnode -f "$_img") || die "mdconfig failed"
    zpool create -m none \
        -O compression=zstd -O atime=off \
        "$POOL_NAME" "/dev/$_md" || die "zpool create failed"
    log "created pool $POOL_NAME on /dev/$_md"
fi

# Create the root dataset at $ROOT if it does not already exist.
if ! zfs list "$POOL_NAME/root" >/dev/null 2>&1; then
    mkdir -p "$(dirname "$ROOT")"
    # ZFS refuses to mount on a non-empty directory.
    if [ -d "$ROOT" ] && [ -n "$(ls -A "$ROOT" 2>/dev/null)" ]; then
        die "$ROOT is non-empty; run './build.sh --clean' before retrying"
    fi
    zfs create -o mountpoint="$ROOT" "$POOL_NAME/root" || \
        die "zfs create root failed"
fi

mkdir -p "$ROOT"
log "workspace ready: $ROOT"