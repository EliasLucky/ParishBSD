#!/bin/sh
# 02-base.sh - fetch, verify, and extract FreeBSD base + kernel.
set -eu
. "$REPO/scripts/lib.sh"
require_root

_manifest="$CACHE/MANIFEST"
fetch "${FREEBSD_MIRROR}/MANIFEST" "$_manifest"

fetch_verified() {
    _name="$1"
    _dest="$CACHE/$_name"
    _expected=$(awk -v n="$_name" '$1==n {print $2}' "$_manifest")
    [ -n "$_expected" ] || die "MANIFEST has no entry for $_name"
    fetch "${FREEBSD_MIRROR}/$_name" "$_dest"
    sha256_verify "$_dest" "$_expected"
}

fetch_verified base.txz
fetch_verified kernel.txz

log "extracting base.txz"
tar -xpf "$CACHE/base.txz" -C "$ROOT" || die "base.txz extraction failed"
log "extracting kernel.txz"
tar -xpf "$CACHE/kernel.txz" -C "$ROOT" || die "kernel.txz extraction failed"

# Refuse if the extraction looks wrong.
[ -x "$ROOT/bin/sh" ] || die "base extraction incomplete: /bin/sh missing"
[ -f "$ROOT/boot/kernel/kernel" ] || die "kernel extraction incomplete"

log "base and kernel installed into $ROOT"