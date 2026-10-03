#!/bin/sh
# Create a jail instance from a personality.
# Usage: 30-create-jail.sh <name> [personality]
# 	<name> instance name (e.g. apps, browser, vault-churchcrm)
# 	<personality> template name (e.g. app-xpra, vault-postgres)
#
# Loads personality metadata from personalities/<personality>/
# Clones the ZFS template if it exists, otherwise extracts base.txz
# Renders e/tc/jail.conf.d/<name>.conf from jail.conf.tmpl
# Installs fstab.<name> if the personality provides one
# Creates mount-point directories
# Optionally installs packages into the jail
#
# Environment variables:
#   PARISHBSD_CACHE cache directory (default /var/cache/parishbsd)
#   PARISHBSD_REPO  repo root (auto-detected from script location)
#   PARISHBSD_FORCE set to 1 to force a re-download
set -eu

# --- variables ---
PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
PARISHBSD_FORCE="${PARISHBSD_FORCE:-0}"

# --- Arguments ---
name="${1:?usage: 30-create-jail.sh <name> <personality>}"
personality="${2:?usage: 30-create-jail.sh <name> <personality>}"

# --- Paths ---
repo="${PARISHBSD_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
personality_dir="$repo/personalities/$personality"
jailroot="/usr/local/jails/${PERSONALITY_TIER:-app}/$name"
arch="$(uname -m)"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
cached_txz="$PARISHBSD_CACHE/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

# --- Helpers
log() { printf '    %s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Sanity
[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v fetch >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 || err "fetch/curl not found"
command -v tar >/dev/null 2>&1 || err "tar not found"

# --- Load personality ---
[ -d "$personality_dir" ] || err "personality '$personality' not found at $personality_dir"
. "$personality_dir/personality.conf" || err "failed to load personality.conf"

tier="$PERSONALITY_TIER"
jailroot="/usr/local/jails/$tier/$name"

# --- Ensure the cache has base.txz (fallback if no ZFS template)
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

	# Prefer ZFS clone from template
	if [ -n "${PERSONALITY_TEMPLATE:-}" ] && zfs list "$PERSONALITY_TEMPLATE" >/dev/null 2>&1; then
		log "Cloning from ZFS template $PERSONALITY_TEMPLATE"
		container_ds="/zroot/jails/containers/$name"
		if zfs list "$container_ds" >/dev/null 2>&1; then
			err "ZFS dataset $container_ds already exists - destroy it first"
		fi
		zfs clone "$PERSONALITY_TEMPLATE" "$container_ds" || err "zfs clone failed"
		zfs set mountpoint="$jailroot" "$container_ds"
		liog "Cloned to $jailroot (dataset: $container_ds)"
	else
		log "No ZFS template found - extracting base.txz"
		ensure_cache
		mkdir -p "$jailroot"
		tar -xpf "$cached_txz" -C "$jailroot" || err "extraction failed"
		rm -f "$jailroot/boot/kernel/kernel" 2>/dev/null || true
		if [ ! -s "$jailroot/etc/resolv.conf" ]; then
			cat > "$jailroot/etc/resolv.conf" <<'EOF'
nameserver 1.1.1.1
nameserver 9.9.9.9
EOF
		fi
		mkdir -p "$jailroot/dev"
		mount -t devfs devfs "$jailroot/dev"
	fi
}

# Render and install the jail config from the personality
install_config() {
	tmpl="$personality_dir/jail.conf.tmpl"
	[ -f "$tmpl" ] || { log "No jail.conf.tmpl for personality $personality - skipping"; return 0; }

	epair_num=$(( $(echo "$name" | cksum | awk '{print $1}') % 1000 ))
	epair="epair${epair_num}"
	ip="10.0.0.$(( epair_num % 200 + 2 ))"

	sed -e "s/\${name}/$name/g" \
	    -e "s/\${tier}/$tier/g" \
	    -e "s/\${epair}/$epair/g" \
	    -e "s/\${ip}/$ip/g" \
	    "$tmpl" > "/etc/jail.conf.d/$name.conf"
	log "Installed /etc/jail.conf.d/$name.conf (epair=$epair, ip=$ip)"

	# Render fstab if provided
	fstab_tmpl="$personality_dir/fstab.tmpl"
	if [ -f "$fstab_tmpl" ]; then
		sed -e "s/\${name}/$name/g" "$fstab_tmpl" > "/etc/fstab.$name" 
		log "Installed /etc/fstab.$name"
	fi
}

# Create mount-point directories
create_mountpoints() {
	if [ "${PERSONAITY_NEEDS_XPRA_DIR:-}" = "yes" ]; then
		mkdir -p "/var/run/xpra/$name"
		mkdir -p "$jailroot/xpra"
		log "Created Xpra mount points for $name"
	fi
	case "$tier" in
		vault)
			mkdir -p "$jailroot/var/db"
			log "Created vault data directory"
			;;
	esac
}

clean_orphan_epairs() {
	for ea in $(ifconfig -l | tr ' ' '\n' | grep '^epair[0-9]*a$'); do
		# If the pair has no bridge membership and no jail is using it destroy
		if ! ifconfig bridge0 2>/dev/null | grep -q "member: $ea"; then
			ifconfig "$ea" destroy 2>/dev/null || true
			log "Destroyed orphan $ea"
		fi
	done
}

# Instal packages (only if jail is running)
install_packages() {
	[ -n "${PERSONALITY_PACKAGES:-}" ] || return 0

	if ! jls name 2>/dev/null | grep -qx "$name"; then
		log "Jail $name not running - skipping package install"
		log "Start it and run: jexec $name pkg install -y $PERSONALITY_PACKAGES"
		return 0
	fi

	log "Installing packages in $name: $PERSONALITY_PACKAGES"
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg bootstrap 2>/dev/null || true
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg install -y $PERSONALITY_PACKAGES || log "Package install failed - run manually later. $PERSONALITY_PACKAGES"
}

ensure_cache
create_jailroot
install_config
create_mountpoints
clean_orphan_epairs

log "Done. Jail '$name' (personality: $personality is ready at $jailroot"
log "Start it with: service jail start $name"
log "Then run packages: jexec $name pkg install -y <package>"
