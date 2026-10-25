#!/bin/sh
# verify-iso.sh  verify a ParishBSD ISO against its signed checksums.
set -eu
ISO="$1"
KEY="${2:-keys/release-key.asc}"
gpg --import "$KEY" 2>/dev/null || true
gpg --verify "${ISO}.sha256.asc" "${ISO}.sha256" || { echo "SHA256 signature INVALID" >&2; exit 1; }
_expected=$(awk '{print $1}' "${ISO}.sha256")
_actual=$(sha256 -q "$ISO")
[ "$_expected" = "$_actual" ] || { echo "SHA256 MISMATCH" >&2; exit 1; }
echo "OK: $ISO"