#!/bin/sh
# mkisoimages.sh - standalone ISO assembler (derived from FreeBSD/helloSystem).
# Usage: mkisoimages.sh <stage-dir> <output.iso> <label> <publisher> <volid>
set -eu
STAGE="$1"; OUT="$2"; LABEL="$3"; PUB="$4"; VOLID="$5"
makefs -t cd9660 \
    -o rockridge \
    -o label="$LABEL" \
    -o publisher="$PUB" \
    -o volid="$VOLID" \
    -o bootimage="boot/efiboot.img" \
    -o no-emul-boot \
    "$OUT" "$STAGE"