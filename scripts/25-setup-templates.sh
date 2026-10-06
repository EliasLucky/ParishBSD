#!/bin/sh
# 25-setup-templates.sh builds ZFS template datasets for ParishBSD jails.
#
# Creates:
#   zroot/jails
#   zroot/jails/templates
#   zroot/jails/templates/<name>      (per personality)
#   zroot/jails/templates/<name>@base (snapshot, the clone source)
#   zroot/jails/containers            (parent for jail instances)
#
# Idempotent: skips templates that already have a @base snapshot
# Pass PARISHBSD_FORCE=1 to rebuild all templates.
#
# Environment:
#   PARISHBSD_CACHE  cache directory (default /var/cache/parishbsd)
#   PARISHBSD_FORCE  set to 1 to rebuild every template
set -eu

PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
PARISHBSD_FORCE="${PARISHBSD_FORCE:-0}"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v zfs >/dev/null 2>&1 || err "zfs not found"
command -v tar >/dev/null 2>&1 || err "tar not found"

log "Ensuring ZFS layout"
zfs list zroot/jails            >/dev/null 2>&1 || zfs create -p zroot/jails
zfs list zroot/jails/templates  >/dev/null 2>&1 || zfs create -p zroot/jails/templates
zfs list zroot/jails/containers >/dev/null 2>&1 || zfs create -p zroot/jails/containers
zfs list zroot/vault-data       >/dev/null 2>&1 || zfs create -p zroot/vault-ddata

zfs set mountpoint=/zroot/jails            zroot/jails            2>/dev/null || true
zfs set mountpoint=/zroot/jails/templates  zroot/jails/templates  2>/dev/null || true
zfs set mountpoint=/zroot/jails/containers zroot/jails/containers 2>/dev/null || true
zfs set mountpoint=/zroot/vault-data       zroot/vault-data       2>/dev/null || true

arch="$(uname -m)"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
cached_txz="$PARISHBSD_CACHE/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

ensure_cache() {
	mkdir -p "$PARISHBSD_CACHE"
	[ -f "$cached_txz" ] && { log "Using cached $cached_txz"; return 0; }
	log "Downloading $url"
	tmp="$cached_txz.part"
	rm -f "$tmp"
	if command -v fetch >/dev/null 2>&1; then
		fetch -o "$tmp" "$url" || err "download failed"
	else
		curl -L -o "$tmp" "$url" || err "download failed"
	fi
	mv "$tmp" "$cached_txz"
	log "Cached ($(du -h "$cached_txz" | awk '{print $1}'))"
}

# Usage: build_template <template-name> "<space-separated packages>"
build_template() {
	tmpl_name="$1" # e.g. app,vault
	pkg_list="$2" # e.g. xpra

	ds="zroot/jails/templates/$tmpl_name"
	mnt="/zroot/jails/templates/$tmpl_name"

	# is the dataset already built?
	if zfs list "$ds@base" >/dev/null 2>&1 && [ "$PARISHBSD_FORCE" != "1" ]; then
		log "Template $ds@base already exists - skipping"
		return 0
	fi

	log "Building template $ds"

	# If the daaset exists but has no @base or if we're forcing then destroy
	if zfs list "$ds" >/dev/null 2>&1; then
		log "  destroying stale $ds"
		zfs destroy -rf "$ds" || err "cannot destroy $ds (is it in use?)"
	fi

	zfs create -p "$ds" || err "cannot create $ds"
	zfs set mountpoint="$mnt" "$ds" 2>/dev/null || true
	mnt="$(zfs get -H -o value mountpoint "$ds")"

	log "  extracting base.txz into $mnt"
	tar -xpf "$cached_txz" -C "$mnt" || err "extraction failed"
	rm -f "$mnt/boot/kernel/kernel" 2>/dev/null || true

	log "  configuring DNS in template"
	cp /etc/resolv.conf "$mnt/etc/resolv.conf" 2>/dev/null || \
		cat > "$mnt/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF

	log "  mounting devfs (needed for pkg inside chroot)"
	mkdir -p "$mnt/dev"
	mount -t devfs devfs "$mnt/dev" || err "cannot mount devfs at $mnt/dev"

	#log "  bootstrapping pkg and installing: $pkg_list"
	log "  disabling FreeBSD-kmods repo (known 404 on FreeBSD 15)"
	# Disable the kmods repo which often causes issues
	mkdir -p "$mnt/usr/local/etc/pkg/repos"
	cat > "$mnt/usr/local/etc/pkg/repos/FreeBSD.conf" <<'EOF'
FreeBSD-kmods: {
	enabled: no
}
EOF

	log "  bootstrapping pkg and installing: $pkg_list"
	if ! chroot "$mnt" /bin/sh -eu <<EOF
env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
env ASSUME_ALWAYS_YES=YES pkg install -y $pkg_list
EOF
	then
		umount "$mnt/dev" || true
		err "pkg install failed in $mnt"
	fi

	log "  unmounting devfs"
	umount "$mnt/dev" || err "cannot unmount $mnt/dev"

	log "  snapshotting $ds@base"
	zfs snapshot "$ds@base" || err "cannot snapshot $ds@base"

	log "  done: $ds@base"
}

ensure_cache

build_template "app"            "xpa"
build_template "vault-postgres" "postgresql16-server postgresql16-client"
build_template "vault-files"    "openssh-portable"

log "All templates built."
log "Verify with: zfs list -t snapshot -r zroot/jails/templates"
