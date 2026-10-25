#!/bin/sh
# 03-packages.sh - build parishbsd-* from parishbsd-ports, install
# everything into the chroot, sign the local repo.
set -eu
. "$REPO/scripts/lib.sh"
require_root
require_cmd openssl

_abi="FreeBSD:$(echo "$FREEBSD_VERSION" | sed 's/-RELEASE//'):amd64"

# ---- bootstrap pkg in the target ----------------------------------------
if [ ! -x "$ROOT/usr/local/sbin/pkg-static" ]; then
    log "bootstrapping pkg in $ROOT"
    pkg -c "$ROOT" bootstrap -f || die "pkg bootstrap failed"
fi

# ---- build parishbsd-* packages (unless a remote repo is configured) ----
if [ -n "$PARISHBSD_PKG_REPO" ]; then
    log "using remote pkg repo: $PARISHBSD_PKG_REPO"
    _repo_url="$PARISHBSD_PKG_REPO"
    _sig_type="pubkey"
    _pubkey_path="/etc/pkg/parishbsd.pub"
    # The caller must have placed the pubkey already; we verify.
    [ -f "$REPO/keys/pkg.pub" ] || \
        die "remote repo configured but keys/pkg.pub is missing"
    mkdir -p "$ROOT/etc/pkg"
    atomic_install "$REPO/keys/pkg.pub" "$ROOT/etc/pkg/parishbsd.pub" 0644
else
    [ -n "$PARISHBSD_PORTS_DIR" ] || die "PARISHBSD_PORTS_DIR is not set"
    [ -d "$PARISHBSD_PORTS_DIR" ] || die "ports dir missing: $PARISHBSD_PORTS_DIR"

    _pkg_repo_dir="$BUILD_DIR/pkg-repo"
    mkdir -p "$_pkg_repo_dir"

    # ---- pkg signing key -------------------------------------------------
    if [ -f "$REPO/keys/pkg.sec" ] && [ -f "$REPO/keys/pkg.pub" ]; then
        _pkg_key="$REPO/keys/pkg.sec"
        _pkg_pub="$REPO/keys/pkg.pub"
        log "using committed pkg signing key"
    else
        _pkg_key="$BUILD_DIR/pkg-key.sec"
        _pkg_pub="$BUILD_DIR/pkg-key.pub"
        if [ ! -f "$_pkg_key" ]; then
            warn "no keys/pkg.sec; generating throwaway dev key"
            warn "this ISO is NOT release-signed; do not distribute it"
            openssl genrsa -out "$_pkg_key" 4096 2>/dev/null || \
                die "openssl genrsa failed"
            openssl rsa -in "$_pkg_key" -pubout -out "$_pkg_pub" 2>/dev/null || \
                die "openssl rsa -pubout failed"
            chmod 600 "$_pkg_key"
        fi
    fi

    # ---- build each port from iso/packages/parishbsd.txt ------------------
    _list="$REPO/iso/packages/parishbsd.txt"
    [ -f "$_list" ] || die "missing port list: $_list"

    while IFS= read -r _port; do
        case "$_port" in ''|\#*) continue ;; esac
        _dir="$PARISHBSD_PORTS_DIR/$_port"
        [ -d "$_dir" ] || die "port not found: $_dir"
        log "building $_port"
        ( cd "$_dir" && \
          env WRKDIRPREFIX="$BUILD_DIR/obj" \
              PACKAGES="$_pkg_repo_dir" \
              BATCH=yes \
              make package ) || die "make package failed: $_port"
    done < "$_list"

    # ---- sign the local repo ---------------------------------------------
    log "signing local repo with $(basename "$_pkg_key")"
    pkg repo "$_pkg_repo_dir" "$_pkg_key" || die "pkg repo sign failed"

    _repo_url="file://$_pkg_repo_dir"
    _sig_type="pubkey"
    _pubkey_path="/etc/pkg/parishbsd.pub"

    # Copy the pubkey into the target and record it for later debug.
    mkdir -p "$ROOT/etc/pkg"
    atomic_install "$_pkg_pub" "$ROOT/etc/pkg/parishbsd.pub" 0644
    cp "$_pkg_pub" "$OUT/pkg-key.pub" 2>/dev/null || true
fi

# ---- pkg repos in the target --------------------------------------------
mkdir -p "$ROOT/usr/local/etc/pkg/repos"

cat > "$ROOT/usr/local/etc/pkg/repos/FreeBSD.conf" <<EOF
FreeBSD: {
  url: "pkg+http://pkg.FreeBSD.org/\${ABI}/latest",
  mirror_type: "srv",
  enabled: yes
}
EOF

cat > "$ROOT/usr/local/etc/pkg/repos/ParishBSD.conf" <<EOF
ParishBSD: {
  url: "${_repo_url}",
  mirror_type: "none",
  signature_type: "${_sig_type}",
  pubkey: "${_pubkey_path}",
  enabled: yes
}
EOF

# ---- install package lists ----------------------------------------------
for _list in base extras; do
    _file="$REPO/iso/packages/${_list}.txt"
    [ -f "$_file" ] || continue
    log "installing package list: $_list"
    # shellcheck disable=SC2046
    pkg -c "$ROOT" install -y -r ParishBSD -r FreeBSD \
        $(grep -v '^#' "$_file" | grep -v '^$') || \
        die "pkg install failed for $_list"
done

log "packages installed"