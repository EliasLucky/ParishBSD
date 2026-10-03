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
set -eu

PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"

repo="${PARISHBSD_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"

log "Ensuring ZFS layout"
zfs list zroot/jails >/dev/null 2>&1 || zfs create -p zroot/jails
zfs list zroot/jails/templates >/dev/null 2>&1 || zfs create -p zroot/jails/templates
zfs list zroot/jails/containers >/dev/null 2>&1 || zfs create -p zroot/jails/containers

arch="$(uname -m)"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
cached_txz="$PARISHBSD_CACHE/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

ensure_cache() {
	mkdir -p "$PARISHBSD_CACHE"
	[ -f "$cached_txz" ] && { log "Using cached $cached_txz"; return 0; }
	log "Downloading $url"
	tmp="$cached_txz.part"; rm -f "$tmp"
	if command -v fetch >/dev/null 2>&1; then
		fetch -o "$tmp" "$url" || err "download failed"
	else
		curl -L -o "$tmp" "$url" || err "download failed"
	fi
	mv "$tmp" "$cached_txz"
}

build_template() {
	tmpl_name="$1" # e.g. app,vault
	personality="$2" # e.g. app-xpra, vault-postgres
	pkg_list="$3" # e.g. xpra

	ds="zroot/jails/templates/$tmpl_name"
	mnt="/zroot/jails/templates/$tmpl_name"

	# is the dataset already built?
	if zfs list "$ds@base" >/dev/null 2>&1; then
		log "Template $ds@base already exists - skipping"
		return 0
	fi

	log "Building template $ds"

	# If the daaset exists but has no @base then destroy
	if zfslist "$ds" >/dev/null 2>&1; then
		log "  destroying stale $ds"
		zfs destroy -rf "$ds"
	fi

	zfs create -p "$ds"
	mnt="$(zfs get -H -o value mountpoint "$ds")"
	[ "$mnt" = "none" ] && { zfs set mountpoint="/zroot/jails/templates/$tmpl_name" "$ds"; mnt="/zroot/jails/templates/$tmpl_name"; }

	log "  extracting base.txz into $mnt"
	tar -xpf "$cached_txz" -C "$mnt" || err "extraction failed"
	rm -f "$mnt/boot/kernel/kernel" 2>/dev/null || true

	log "  configuring DNS"
	cp /etc/resolv.conf "$mnt/etc/resolv.conf" 2>/dev/null || \
		cat > "$mnt/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF

	log"  mounting devfs"
	mkdir -p "$mnt/dev"
	mount -t devfs devfs "$mnt/dev"

	log "  bootstrapping pkg and installing: $pkg_list"
	# Disable the kmods repo which often causes issues
	mkdir -p "$mnt/usr/local/etc/pkg/repos"
	cat > "$mnt/usr/local/etc/pkg/repos/FreeBSD.conf" <<'EOF'
FreeBSD-kmods: {
	enabled: no
}
EOF

	chroot "$mnt" /bin/sh -eu <<EOF
env ASSUME_ALWAYS_YES=YES pkg bootstrap -f
env ASSUME_ALWAYS_YES=YES pkg install -y $pkg_list
EOF

	log "  unmounting devfs"
	umount "$mnt/dev"

	log "  snapshotting $ds@base"
	zfs snapshot "$ds@base"

	log "  done: $ds@base"
}

ensure_cache

build_template app   app-xpra       "xpa"
build_template vault vault-postgres "postgresql16-server"

log "All templates built."
