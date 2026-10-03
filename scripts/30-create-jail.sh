#!/bin/sh
# Create a jail root and install its config.
# Usage: 30-create-jail.sh <name> [tier]
# 	<name> name of the jail (e.g. browser, vault-churchcrm)
# 	[tier] app | vault (default: app). Vault names auto-detect.
set -eu

name="${1:?usage: 30-create-jail.sh <name> [tier]}"
tier="${2:-app}"
case "$name" in
	vault*|*vault) tier=vault ;;
esac
repo="${PARISHBSD_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
cache="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
jailroot="/usr/local/jails/$tier/$name"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
arch="$(uname -m)"

cached_txz="$cache/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v fetch >/dev/null || err "fetch not found"
command -v tar >/dev/null || err "tar not found"

# Ensure the cache has base.txz
ensure_cache() {
	mkdir -p "$cache"
	if [ -f "$cached_txz" ] && [ "${PARISHBSD_FORCE:-0}" != "1" ]; then
		log "Using cached $cached_txz"
		return 0
	fi


	log "Downloading base.txz for $version/$arch"
	log "  from $url"
	log "  to $cached_txz"

	# Download to a temp file, then rename automatically so an interrupted
	tmp="$cached_txz.part"
	rm -rf "$tmp"
	fetch -o "$tmp" "$url" || err "download failed"
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
	#if [ ! -s "$jailrroot/etc/resolv.conf" ]; then
	#	cat > "$jailroot/etc/resolv.conf" << 'EOF'
#nameserver 1.1.1.1
#nameserver 9.9.9.9
#EOF		
#	fi
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
		install -m 0644 "$stab" "/etc/fstab.$name"
		log "Installed /etc/fstab.$name"
	fi

	# Create mount point directories
	case "$name" in
		browser)
			mkdir -p /var/run/xpra/browser
			mkdir -p "/usr/local/jails/app/browser/xpra"
			;;
		vault-*)
			mkdir -p "/usr/local/jails/vault/$name/var/db"
			;;
	esac
}

ensure_cache
create_jailroot
install_config

log "Done. Jail '$name' is ready at $jailroot"
log "Start it with: service jail start $name"
