#!/bin/sh
# 30-create-jail.sh — create a jail instance from a personality.
#
# Usage: sh 30-create-jail.sh <name> <personality>
#   <name>          instance name (e.g. apps, browser, vault-churchcrm)
#   <personality>   template name (e.g. app-xpra, vault-postgres)
#
# Loads personality metadata from personalities/<personality>/.
# Clones the ZFS template if it exists, otherwise extracts base.txz.
# Renders /etc/jail.conf.d/<name>.conf from jail.conf.tmpl.
# Installs /etc/fstab.<name> if the personality provides one.
# Installs provision.sh into the jail and wires up /etc/rc.local so it
# runs on every jail start.
# Creates mount-point directories.
# Optionally installs packages into the jail (if it is already running).
#
# Idempotent: an existing jail root is left alone.
#
# Environment:
#   PARISHBSD_CACHE   cache directory (default /var/cache/parishbsd)
#   PARISHBSD_REPO    repo root (auto-detected from script location)
#   PARISHBSD_FORCE   1 to force a re-download of base.txz
set -eu

PARISHBSD_CACHE="${PARISHBSD_CACHE:-/var/cache/parishbsd}"
PARISHBSD_FORCE="${PARISHBSD_FORCE:-0}"

log()  { printf '    %s\n' "$*"; }
row()  { printf '    %-22s %s\n' "$1" "$2"; }
err()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Arguments ---
name="${1:?usage: 30-create-jail.sh <name> <personality>}"
personality="${2:?usage: 30-create-jail.sh <name> <personality>}"

# --- Paths ---
repo="${PARISHBSD_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
personality_dir="$repo/personalities/$personality"
arch="$(uname -m)"
version="$(freebsd-version -u | awk -F'-p' '{print $1}')"
cached_txz="$PARISHBSD_CACHE/base-$version-$arch.txz"
url="https://download.freebsd.org/releases/$arch/$version/base.txz"

# --- Sanity ---
[ "$(id -u)" -eq 0 ] || err "must be run as root"
command -v fetch >/dev/null 2>&1 || command -v curl >/dev/null 2>&1 \
    || err "fetch/curl not found"
command -v tar >/dev/null 2>&1 || err "tar not found"

# --- Load personality ---
[ -d "$personality_dir" ] || err "personality '$personality' not found at $personality_dir"
# shellcheck disable=SC1091
. "$personality_dir/personality.conf" || err "failed to load personality.conf"

# Defaults
PERSONALITY_TIER="${PERSONALITY_TIER:-app}"
PERSONALITY_TEMPLATE="${PERSONALITY_TEMPLATE:-}"
PERSONALITY_PACKAGES="${PERSONALITY_PACKAGES:-}"
PERSONALITY_NEEDS_XPRA_DIR="${PERSONALITY_NEEDS_XPRA_DIR:-no}"
PERSONALITY_DATA_MOUNT="${PERSONALITY_DATA_MOUNT:-/var/db/data}"
PERSONALITY_DATA_SOURCE="${PERSONALITY_DATA_SOURCE:-/zroot/vault-data}"
PERSONALITY_PROVISION="${PERSONALITY_PROVISION:-}"

tier="$PERSONALITY_TIER"
jailroot="/usr/local/jails/$tier/$name"

# --- Cache ---
ensure_cache() {
	mkdir -p "$PARISHBSD_CACHE"
	if [ -f "$cached_txz" ] && [ "$PARISHBSD_FORCE" != "1" ]; then
		row "base.txz" "using cache"
		return 0
	fi

	log "Downloading base.txz for $version/$arch"
	tmp="$cached_txz.part"
	rm -f "$tmp"
	if command -v fetch >/dev/null 2>&1; then
		fetch -o "$tmp" "$url" || err "download failed"
	else
		curl -L -o "$tmp" "$url" || err "download failed"
	fi
	mv "$tmp" "$cached_txz"
	row "base.txz" "cached ($(du -h "$cached_txz" | awk '{print $1}'))"
}

# --- Jail root (ZFS clone preferred, extraction as fallback) ---
create_jailroot() {
	if [ -d "$jailroot" ] && [ -e "$jailroot/bin/sh" ]; then
		row "jail root" "already exists - leaving alone"
		return 0
	fi

	if [ -n "$PERSONALITY_TEMPLATE" ] && \
		zfs list "$PERSONALITY_TEMPLATE" >/dev/null 2>&1; then

		pool="${PERSONALITY_TEMPLATE%%/*}"
		container_ds="${pool}/jails/containers/$name"
		containers_parent="${container_ds%/*}"

		zfs list "$containers_parent" >/dev/null 2>&1 || \
			zfs create -p "$containers_parent" || \
			err "cannot create $containers_parent"

		if zfs list "$container_ds" >/dev/null 2>&1; then
			err "ZFS dataset $container_ds already exists - destroy it first"
		fi

		log "Cloning template"
		zfs clone "$PERSONALITY_TEMPLATE" "$container_ds" || err "zfs clone failed"
		zfs set mountpoint="$jailroot" "$container_ds" || err "cannot set mountpoint"
    	row "jail root" "$jailroot (cloned)"
    else
    	log "No ZFS template - extracting base.txz"
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
		row "jail root" "$jailroot (extracted)"
	fi
}

# --- Config, fstab, provision ---
install_config() {
	# Render jail.conf.d/<name>.conf
	tmpl="$personality_dir/jail.conf.tmpl"
	if [ -f "$tmpl" ]; then
		epair_num=$(( $(echo "$name" | cksum | awk '{print $1}') % 1000 ))
		epair="epair${epair_num}"
		ip="10.0.0.$(( epair_num % 200 + 2 ))"

		install -d /etc/jail.conf.d
		sed -e "s/\${name}/$name/g" \
			-e "s/\${tier}/$tier/g" \
			-e "s/\${epair}/$epair/g" \
			-e "s/\${ip}/$ip/g" \
			-e "s|\${PERSONALITY_DATA_MOUNT}|$PERSONALITY_DATA_MOUNT|g" \
			-e "s|\${PERSONALITY_DATA_SOURCE}|$PERSONALITY_DATA_SOURCE|g" \
			"$tmpl" > "/etc/jail.conf.d/$name.conf"
		row "jail.conf" "$name.conf (epair=$epair ip=$ip)"
	else
		row "jail.conf" "no template - skipped"
	fi

	# Render fstab.<name> if the personality provides one
	fstab_tmpl="$personality_dir/fstab.tmpl"
	if [ -f "$fstab_tmpl" ]; then
		sed -e "s/\${name}/$name/g" \
			-e "s/\${tier}/$tier/g" \
			-e "s|\${PERSONALITY_DATA_MOUNT}|$PERSONALITY_DATA_MOUNT|g" \
			-e "s|\${PERSONALITY_DATA_SOURCE}|$PERSONALITY_DATA_SOURCE|g" \
			"$fstab_tmpl" > "/etc/fstab.$name"
		row "fstab" "$name"
	fi

	# Install provision.sh and the rc.local hook
	if [ -n "$PERSONALITY_PROVISION" ]; then
		prov="$personality_dir/$PERSONALITY_PROVISION"
		if [ -f "$prov" ]; then
			install -d "$jailroot/usr/local/etc/parishbsd"
			install -m 0755 "$prov" "$jailroot/usr/local/etc/parishbsd/provision.sh"
			row "provision.sh" "installed"

			rclocal="$jailroot/etc/rc.local"
			if [ ! -f "$rclocal" ] || \
				! grep -q 'parishbsd/provision.sh' "$rclocal" 2>/dev/null; then
				cat > "$rclocal" <<'EOF'
#!/bin/sh
# ParishBSD provisioning hook — runs on every jail start.
if [ -x /usr/local/etc/parishbsd/provision.sh ]; then
    /usr/local/etc/parishbsd/provision.sh
fi
exit 0
EOF
				chmod 0755 "$rclocal"
				row "rc.local" "provisioning hook installed"
			fi
		else
			row "provision.sh" "WARN: $prov not found"
		fi
	fi
}

# --- Mount points ---
create_mountpoints() {
	if [ "$PERSONALITY_NEEDS_XPRA_DIR" = "yes" ]; then
		mkdir -p "/var/run/xpra/$name"
		mkdir -p "$jailroot/xpra"
		row "xpra dirs" "/var/run/xpra/$name"
	fi

	case "$tier" in
		vault)
			mkdir -p "$jailroot$PERSONALITY_DATA_MOUNT"
    		row "data dir" "$jailroot$PERSONALITY_DATA_MOUNT"
			;;
	esac
}

# --- Orphan epair cleanup ---
clean_orphan_epairs() {
	cleaned=0
	for ea in $(ifconfig -l | tr ' ' '\n' | grep '^epair[0-9]*a$' 2>/dev/null); do
		if ! ifconfig bridge0 2>/dev/null | grep -q "member: $ea"; then
			ifconfig "$ea" destroy 2>/dev/null && cleaned=$((cleaned + 1))
		fi
	done
	[ "$cleaned" -gt 0 ] && row "orphan epairs" "destroyed $cleaned"
	return 0
}

# --- Package install (only if the jail is already running) ---
install_packages() {
	[ -n "$PERSONALITY_PACKAGES" ] || return 0

	if ! jls name 2>/dev/null | grep -qx "$name"; then
		row "packages" "jail not running - skipped"
		row ""         "start it and run: jexec $name pkg install -y $PERSONALITY_PACKAGES"
		return 0
	fi

	log "Installing packages: $PERSONALITY_PACKAGES"
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg bootstrap 2>/dev/null || true
	jexec "$name" env ASSUME_ALWAYS_YES=YES pkg install -y $PERSONALITY_PACKAGES \
		|| row "packages" "install failed - run manually later"
}

create_jailroot
install_config
create_mountpoints
clean_orphan_epairs
install_packages

row "personality" "$personality"
row "tier"        "$tier"
log "Jail '$name' is ready."
log "Start it with: service jail start $name"
