#!/bin/sh
# 00-preflight.sh  refuse early if the host cannot build this ISO.
set -eu
. "$REPO/scripts/lib.sh"

require_root
require_cmd zpool zfs mdconfig makefs mkuzip sha256 fetch python3

# Host FreeBSD major must match the base we are fetching.
_host_major=$(freebsd-version -u | cut -d. -f1)
_base_major=$(echo "$FREEBSD_VERSION" | cut -d. -f1)
[ "$_host_major" = "$_base_major" ] || \
    die "host FreeBSD major ($_host_major) != base major ($_base_major)"

# Signing key must be set if --sign was requested.
# (SIGN is not exported; 09-sign checks again.)

# Disk space: pool size + 2 GB headroom.
_avail=$(df -k "$BUILD_DIR" | awk 'NR==2 {print $4}')
_need_kb=$(( $(echo "$POOL_SIZE" | sed 's/g$//') * 1024 * 1024 + 2097152 ))
[ "$_avail" -ge "$_need_kb" ] || \
    die "insufficient space in $BUILD_DIR: need ${_need_kb}K, have ${_avail}K"

log "preflight OK (host $_host_major, base $FREEBSD_VERSION)"