#!/bin/sh
# build.sh - ParishBSD ISO build orchestrator.
#
# Usage:
#   sudo ./build.sh                 # full build
#   sudo ./build.sh --from 04       # resume from phase 04 (snapshots)
#   sudo ./build.sh --only 08       # run only phase 08
#   sudo ./build.sh --sign          # sign the ISO after 08
#   sudo ./build.sh --clean         # destroy the build pool, keep cache
#   sudo ./build.sh --clean-all     # destroy pool and cache
#
# Exit codes: 0 success, 1 failure, 2 usage.

set -eu

REPO=$(cd "$(dirname "$0")" && pwd)
. "$REPO/VERSION"
VERSION=${VERSION:-0.0.0}

# Parse args before sourcing build.conf so --help works without config.
FROM=0
ONLY=0
SIGN=0
CLEAN=0
CLEAN_ALL=0
for _arg in "$@"; do
    case "$_arg" in
        --from)     shift; FROM=$1 ;;
        --from=*)   FROM=${_arg#*=} ;;
        --only)     shift; ONLY=$1 ;;
        --only=*)   ONLY=${_arg#*=} ;;
        --sign)     SIGN=1 ;;
        --clean)    CLEAN=1 ;;
        --clean-all) CLEAN=1; CLEAN_ALL=1 ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) die "unknown argument: $_arg" ;;
    esac
done

. "$REPO/build.conf"
. "$REPO/scripts/lib.sh"

# Export for phases.
export VERSION FREEBSD_VERSION FREEBSD_MIRROR POOL_NAME POOL_SIZE \
       BUILD_DIR ROOT OUT STAGE CACHE ISO_LABEL ISO_PUBLISHER ISO_VOLID \
       ISO_NAME SIGNING_KEY PORTS_OVERLAY PARISHBSD_PKG_REPO \
       MFSROOT_SIZE UZIP_BLOCK_SIZE UZIP_COMPRESS REPO

require_root
require_cmd zpool zfs mdconfig makefs mkuzip sha256 gpg

mkdir -p "$BUILD_DIR" "$OUT" "$STAGE" "$CACHE"

# ---- clean -----------------------------------------------------------------
if [ "$CLEAN" -eq 1 ]; then
    if zpool list "$POOL_NAME" >/dev/null 2>&1; then
        log "destroying pool $POOL_NAME"
        zpool destroy -f "$POOL_NAME" || warn "pool destroy failed"
    fi
    rm -rf "$ROOT" "$STAGE" "$PORTS_OVERLAY"
    rm -f "$BUILD_DIR/.parishbsd-phase-"*
    [ "$CLEAN_ALL" -eq 1 ] && rm -rf "$CACHE"
    log "clean complete"
    [ "$ONLY" -eq 0 ] && [ "$FROM" -eq 0 ] || exit 0
fi

# ---- phase runner ----------------------------------------------------------
PHASES=00-preflight 01-workspace 02-base 03-packages 04-config \
        05-boot 06-compress 07-ramdisk 08-image 09-sign

run_phase() {
    _num=${1%%-*}
    _name=$1
    _script="$REPO/iso/phases/${_name}.sh"
    [ -x "$_script" ] || die "phase script missing: $_script"

    if [ "$ONLY" -ne 0 ] && [ "$_num" != "$ONLY" ]; then
        return 0
    fi
    if [ "$FROM" -ne 0 ] && [ "$_num" -lt "$FROM" ]; then
        if phase_done "$_num"; then
            log "skip phase $_name (cached)"
            return 0
        fi
        warn "phase $_name has no snapshot; running anyway"
    fi
    if phase_done "$_num" && [ "$ONLY" -eq 0 ]; then
        log "skip phase $_name (marker present)"
        return 0
    fi

    log "=== phase $_name ==="
    PHASE=$_name sh -eu "$_script" || die "phase $_name failed"
    mark_phase "$_num"
}

# ---- sign-only shortcut ----------------------------------------------------
if [ "$ONLY" = "09" ]; then
    run_phase 09-sign
    exit 0
fi

for _p in $PHASES; do
    run_phase "$_p"
done

# ---- explicit sign after 08 -----------------------------------------------
if [ "$SIGN" -eq 1 ] && [ "$ONLY" -eq 0 ]; then
    run_phase 09-sign
fi

log "build complete: $OUT/$ISO_NAME"