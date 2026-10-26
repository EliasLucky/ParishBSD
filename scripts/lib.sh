#!/bin/sh
# lib.sh - shared helpers for ParishBSD build phases.
# Every phase sources this. No `set -e` here.

: "${BUILD_DIR:?lib.sh: BUILD_DIR not set}"
: "${ROOT:?lib.sh: ROOT not set}"

# ---- logging --------------------------------------------------------------
_ts() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log()  { printf '%s [%s] %s\n' "$(_ts)" "${PHASE:-build}" "$*" >&2; }
warn() { printf '%s [%s] WARNING: %s\n' "$(_ts)" "${PHASE:-build}" "$*" >&2; }
err()  { printf '%s [%s] ERROR: %s\n' "$(_ts)" "${PHASE:-build}" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---- guards ---------------------------------------------------------------
require_root() {
    [ "$(id -u)" -eq 0 ] || die "this phase must run as root"
}
require_cmd() {
    for _c in "$@"; do
        command -v "$_c" >/dev/null 2>&1 || die "required command not found: $_c"
    done
}
require_file() {
    [ -f "$1" ] || die "required file not found: $1"
}

# ---- atomic install -------------------------------------------------------
# atomic_install SRC DST [MODE]
# Copy SRC to DST via a temp file in the same directory, then rename.
# Refuses to follow symlinks at DST.
atomic_install() {
    _src="$1"; _dst="$2"; _mode="${3:-0644}"
    _dir=$(dirname "$_dst")
    [ -d "$_dir" ] || die "atomic_install: destination dir missing: $_dir"
    if [ -L "$_dst" ]; then
        die "atomic_install: refusing to replace symlink: $_dst"
    fi
    _tmp="${_dir}/.tmp.$$.$(basename "$_dst")"
    install -m "$_mode" "$_src" "$_tmp" || die "atomic_install: copy failed"
    mv -f "$_tmp" "$_dst" || die "atomic_install: rename failed"
}

# ---- checksum -------------------------------------------------------------
sha256_verify() {
    _file="$1"; _expected="$2"
    _got=$(sha256 -q "$_file") || die "sha256 failed on $_file"
    [ "$_got" = "$_expected" ] || die "SHA256 mismatch for $_file: expected $_expected, got $_got"
}

# ---- chroot ---------------------------------------------------------------
# Run a command inside $ROOT with a clean environment.
chroot_run() {
    env -i \
        PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin \
        HOME=/root \
        TERM="${TERM:-dumb}" \
        ASSET=/ \
        chroot "$ROOT" "$@"
}

# ---- phase markers (snapshot caching) -------------------------------------
phase_marker() { printf '%s/.parishbsd-phase-%s' "$BUILD_DIR" "$1"; }
phase_done()   { [ -f "$(phase_marker "$1")" ]; }
mark_phase()   { : > "$(phase_marker "$1")"; }

# ---- sha256 fetch helper --------------------------------------------------
fetch() {
    _url="$1"; _out="$2"
    if [ -f "$_out" ]; then
        log "cache hit: $(basename "$_out")"
        return 0
    fi
    log "fetch: $_url"
    /usr/bin/fetch -q -o "${_out}.tmp" "$_url" || die "fetch failed: $_url"
    mv -f "${_out}.tmp" "$_out"
}