#!/bin/sh
set -eu

REPO="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO"

echo "==> Checking prerequisites"
[ "$(id -u)" -eq 0 ] || { echo "must run as root"; exit 1; }
[ -d /usr/src/.git ] || echo "warning: /usr/src is not a git checkout"

echo "==> Installing host packages"
pkg install -y xpra bsddialog

echo "==> Applying overlays to /etc"
for f in $(find overlays/etc -type f); do
	dest="/${f#overlays/}"
	mkdir -p "$(dirname "$dest")"
	cp -v "$f" "$dest"
done

echo "==> Setting up network"
sh scripts/01-network.sh

echo "==> Creating jails"
sh scripts/02-create-jails.sh

echo "==> Installing xpra into jailrs"
sh scripts/03-install-xpra.sh

echo "==> Configuring vault"
sh scripts/04-configre-vault.sh

echo "==> Enabling services"
sysrc jail_enable=YES
sysrc pf_enable=YES
sysrc gateway_enabled=YES
sysrc parishbsd_enable=YES

echo "==> Done. Reboot to start ParishBSD."
