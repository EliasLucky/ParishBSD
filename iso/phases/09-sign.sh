#!/bin/sh
# 09-sign.sh  detached GPG signatures over SHA256 and SHA512 sums.
set -eu
. "$REPO/scripts/lib.sh"
require_root
require_cmd gpg sha256 sha512

_iso="$OUT/$ISO_NAME"
[ -f "$_iso" ] || die "ISO not found: $_iso"

[ -n "$SIGNING_KEY" ] || \
    die "SIGNING_KEY is empty; set PARISHBSD_SIGNING_KEY to a GPG key ID"

# Refuse to sign if the key is not present in the keyring.
gpg --list-secret-keys "$SIGNING_KEY" >/dev/null 2>&1 || \
    die "signing key not found in keyring: $SIGNING_KEY"

_sha256="$OUT/${ISO_NAME}.sha256"
_sha512="$OUT/${ISO_NAME}.sha512"

( cd "$OUT" && sha256 -q "$ISO_NAME" > "$(basename "$_sha256")" )
( cd "$OUT" && sha512 -q "$ISO_NAME" > "$(basename "$_sha512")" )

for _sum in "$_sha256" "$_sha512"; do
    _asc="${_sum}.asc"
    rm -f "$_asc"
    gpg --batch --yes --armor --detach-sign \
        --local-user "$SIGNING_KEY" \
        --output "$_asc" "$_sum" || die "gpg sign failed: $_sum"
done

log "signed: $OUT/${ISO_NAME}.sha256.asc"
log "signed: $OUT/${ISO_NAME}.sha512.asc"