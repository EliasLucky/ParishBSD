#!/bin/sh
# signing-keygen.sh — one-time creation of the ParishBSD release key.
# Run OFFLINE. Never commit the secret key.
set -eu
: "${PARISHBSD_KEY_UID:=ParishBSD Release <release@parishbsd.org>}"
gpg --batch --full-generate-key <<EOF
Key-Type: eddsa
Key-Curve: ed25519
Key-Usage: sign
Name-Real: ParishBSD Release
Name-Email: release@parishbsd.org
Expire-Date: 2y
%commit
EOF
gpg --armor --export "$PARISHBSD_KEY_UID" > release-key.asc
echo "Secret key created. Back it up offline. Public key: release-key.asc"