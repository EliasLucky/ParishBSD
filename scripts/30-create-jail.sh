#!/bin/sh
# Create a jail root and install its config.
# Usage: 30-create-jail.sh <name> [tier]
# 	<name> name of the jail (e.g. browser, vault-churchcrm)
# 	[tier] app | vault (default: app). Vault names auto-detect.
set -eu

PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
PARISHBSD_FORCE="${PARISHBSD_FORCE:-0}"

name="${1:?usage: 30-create-jail.sh <name> [tier]}"
tier="${2:-app}"
case "$name" in
	vault*|*vault) tier=vault ;;
esac
repo="${PARISHBSD_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
jailroot="/usr/local/jails/$tier/$name"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
arch="$(uname -m)"

cached_txz="$PARISHBSD_CACHE/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v fetch >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || err "fetch not found"
command -v tar >/dev/null 2>&1 || err "tar not found"

# Ensure the cache has base.txz
ensure_cache() {
	mkdir -p "$PARISHBSD_CACHE"
	if [ -f "$cached_txz" ] && [ "$PARISHBSD_FORCE" != "1" ]; then
		log "Using cached $cached_txz"
		return 0
	fi


	log "Downloading base.txz for $version/$arch"
	log "  from $url"
	log "  to $cached_txz"

	tmp="$cached_txz.part"
	rm -rf "$tmp"

	if command -v fetch >/dev/null 2>&1; then
		fetch -o "$tmp" "$url" || err "download failed"
	else
		curl -L -o "$tmp" "$url" || err "download failed"
	fi

	mv "$tmp" "$cached_txz"

	log "Cached ($(du -h "$cached_txz" | awk '{print $1}'))"
}

# Extract into the jail root
create_jailroot() {
	if [ -d "$jailroot" ] && [ -e "$jailroot/bin/sh" ]; then
		log "Jail root $jailroot already exists - leaving it alone"
		return 0
	fi

	log "Creating jail root at $jailroot"
	mkdir -p "$jailroot"

	log "Extracting base.txz"
	tar -xpf "$cached_txz" -C "$jailroot" || err "extraction failed"

	# A jail does not need its own kernel
	rm -f "$jailroot/boot/kernel/kernel" 2>/dev/null || true

	# Ensure resolv.conf exists
	if [ ! -s "$jailrroot/etc/resolv.conf" ]; then
		cat > "$jailroot/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF		
	fi
}

# Install the jail config from the repo
install_config() {
	cfg="$repo/host/etc/jail.conf.d/$name.conf"
	if [ ! -f "$cfg" ]; then
		log "No jail for '$name' at $cfg - skipping"
		return 0
	fi

	install -d /etc/jail.conf.d
	install -m 0644 "$cfg" "/etc/jail.conf.d/$name.conf"
	log "Installed /etc/jail.conf.d/$name.conf"

	# Install the fstab entry if the repo has one
	fstab="$repo/host/etc/fstab.$name"
	if [ -f "$fstab" ]; then
		install -m 0644 "$fstab" "/etc/fstab.$name"
		log "Installed /etc/fstab.$name"
	fi
}

# Create mount-point directories the jail needs
create_mountpoints() {
	case "$name" in
		browser|*)
			if [ "$tier" = "app" ]; then
				mkdir -p "/var/run/xpra/$name"
				mkdir -p "$jailroot/xpra"
				log "Created Xpra mount points for $name"
			fi
			;;
	esac

	case "$name" in
		vault-*|*vault*)
			mkdir -p "$jailroot/var/db"
			log "Created vault data directory"
			;;
	esac
}

clean_orphan_epairs() {
	# If a jail was killed uncleanly
	for ea in $(ifconfig -l | tr ' ' '\n' | grep '^epair[0-9]*a$'); do
		pair="${ea%a}b"
		# If the pair has no bridge membership and no jail is using it destroy i
		if ! ifconfig bridge0 2>/dev/null | grep -q "member: $ea"; then
			ifconfig "$ea" destroy 2>/dev/null || true
			log "Destroyed orphan $ea"
		fi
	done
}

install_packages() {
	case "$name" in
		browser|desktop|office|churchcrm-ui)
			pkgs="xpra"
			;;
		vault-*)
			pkgs="postgresql16-server"
			;;
		*)
			pkgs=""
			;;
	esac

	[ -n "$pkgs" ] || return 0

	if ! jls name 2>/dev/null | grep -qx "$name"; then
		log "Jail $name not running - skipping package install"
		log "Start it and run: jexec $name pkg install -y $pkgs"
		return 0
	fi

	log "Installing packages in $name: $pkgs"
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg bootstrap 2>/dev/null || true
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg install -y $pkgs || log "Package install failed - run manually later"
}

ensure_cache
create_jailroot
install_config
create_mountpoints
clean_orphan_epairs

log "Done. Jail '$name' is ready at $jailroot"
log "Start it with: service jail start $name"
log "Then run packages: jexec $name pkg install -y <package>"
