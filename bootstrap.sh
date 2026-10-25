#!/bin/sh
# bootstrap.sh - DEPRECATED.
cat >&2 <<'EOF'
bootstrap.sh is retired. ParishBSD is built as an ISO; use:

  sudo ./build.sh                 # build the ISO
  sudo ./provision.sh             # dev convenience on a FreeBSD VM

bootstrap.sh did not produce a reproducible artifact and could not be
signed. It will be removed after the 1.0.6 release cycle.
EOF
exit 1