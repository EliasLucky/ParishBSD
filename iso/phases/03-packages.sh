#!/bin/sh
# 03-packages.sh - bootstrap pkg in the chroot and install package lists.
set -eu
. "$REPO/scripts/lib.sh"
require_root

# ABI for pkg -c; must match the base we extracted.
_abi="FreeBSD:$(echo "$FREEBSD_VERSION" | sed 's/-RELEASE//'):amd64"

# Bootstrap pkg-static inside the target.
if [ ! -x "$ROOT/usr/local/sbin/pkg-static" ]; then
    log "bootstrapping pkg in $ROOT"
    pkg -c "$ROOT" bootstrap -f || die "pkg bootstrap failed"
fi

# Copy staging ports into the local overlay.
mkdir -p "$PORTS_OVERLAY"
for _p in "$REPO"/packages/parishbsd-*; do
    _name=$(basename "$_p")
    rm -rf "$PORTS_OVERLAY/$_name"
    cp -R "$_p" "$PORTS_OVERLAY/$_name"
done

# Build the parishbsd-* packages from the staging overlay, unless the
# caller points at a remote repo.
if [ -n "$PARISHBSD_PKG_REPO" ]; then
    _repo_url="$PARISHBSD_PKG_REPO"
else
    log "building parishbsd-* packages locally"
    ( cd "$PORTS_OVERLAY" && \
      env PORTSDIR="$PORTS_OVERLAY" make clean package \
          BATCH=yes WRKDIRPREFIX="$BUILD_DIR/obj" \
          PACKAGES="$BUILD_DIR/pkg-repo" ) || \
        die "local package build failed"
    _repo_url="file://$BUILD_DIR/pkg-repo"
fi

# Point pkg at the repo.
mkdir -p "$ROOT/usr/local/etc/pkg/repos"
cat > "$ROOT/usr/local/etc/pkg/repos/parishbsd.conf" <<EOF
ParishBSD: {
  url: "${_repo_url}",
  mirror_type: "none",
  signature_type: "pubkey",
  pubkey: "/etc/pkg/parishbsd.pub",
  enabled: yes
}
EOF
cp "$REPO/keys/pkg.pub" "$ROOT/etc/pkg/parishbsd.pub"

# Install package lists.
for _list in base extras; do
    _file="$REPO/iso/packages/${_list}.txt"
    [ -f "$_file" ] || continue
    log "installing package list: $_list"
    # shellcheck disable=SC2046
    pkg -c "$ROOT" install -y \
        -r ParishBSD \
        $(grep -v '^#' "$_file" | grep -v '^$') || \
        die "pkg install failed for $_list"
done

log "packages installed"