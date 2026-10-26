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
# early die() before sourcing lib.sh
die() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --from)       FROM=$2;  shift 2 ;;
        --from=*)     FROM=${1#*=}; shift ;;
        --only)       ONLY=$2;  shift 2 ;;
        --only=*)     ONLY=${1#*=}; shift ;;
        --sign)       SIGN=1; shift ;;
        --clean)      CLEAN=1; shift ;;
        --clean-all)  CLEAN=1; CLEAN_ALL=1; shift ;;
        -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown argument: $1" ;;
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

# ---- resolve parishbsd-ports ----------------------------------------------
if [ -z "$PARISHBSD_PKG_REPO" ]; then
    if [ -z "$PARISHBSD_PORTS_DIR" ] || [ ! -d "$PARISHBSD_PORTS_DIR" ]; then
        PARISHBSD_PORTS_DIR="$BUILD_DIR/parishbsd-ports"

        if [ ! -d "$PARISHBSD_PORTS_DIR/.git" ]; then
            log "cloning $PARISHBSD_PORTS_REPO → $PARISHBSD_PORTS_DIR"
            require_cmd git

            # Codeberg's HTTP/2 front end resets large transfers. HTTP/1.1,
            # a shallow single-branch clone, and a larger post buffer are the
            # documented workaround.
            _clone_ok=0
            if git -c http.version=HTTP/1.1 \
                   -c http.postBuffer=524288000 \
                   clone --depth=1 --single-branch \
                   --branch "$PARISHBSD_PORTS_BRANCH" \
                   "$PARISHBSD_PORTS_REPO" "$PARISHBSD_PORTS_DIR"; then
                _clone_ok=1
            else
                warn "clone failed; removing partial checkout and retrying with blob filter"
                rm -rf "$PARISHBSD_PORTS_DIR"
                if git -c http.version=HTTP/1.1 \
                       -c http.postBuffer=524288000 \
                       clone --depth=1 --single-branch --filter=blob:none \
                       --branch "$PARISHBSD_PORTS_BRANCH" \
                       "$PARISHBSD_PORTS_REPO" "$PARISHBSD_PORTS_DIR"; then
                    _clone_ok=1
                fi
            fi

            [ "$_clone_ok" -eq 1 ] || die "failed to clone $PARISHBSD_PORTS_REPO (see warnings above)"
        fi
    fi
fi
export PARISHBSD_PORTS_DIR
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
PHASES="00-preflight 01-workspace 02-base 03-packages 04-config 05-boot 06-compress 07-ramdisk 08-image 09-sign"

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