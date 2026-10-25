#!/bin/sh
# provision.sh  apply ParishBSD packages to a running FreeBSD system.
# DEVELOPMENT CONVENIENCE. Runs as root and
# installs packages from the configured repo.
set -eu

[ "$(id -u)" -eq 0 ] || { echo "provision.sh: must be root" >&2; exit 1; }

if [ ! -f /etc/os-release ] || ! grep -q '^ID=freebsd' /etc/os-release 2>/dev/null; then
    echo "provision.sh: this system does not appear to be stock FreeBSD" >&2
    exit 1
fi

REPO=$(cd "$(dirname "$0")" && pwd)
. "$REPO/VERSION"

pkg install -y \
    parishbsd-base \
    parishbsd-artwork \
    parishbsd-compartments \
    parishbsd-guardian \
    parishbsd-about

sysrc parish_guardian_enable=YES
sysrc parishbsd_vaults_enable=YES
sysrc dbus_enable=YES
sysrc lightdm_enable=YES

echo "ParishBSD ${VERSION} provisioned. Reboot to see the full effect."
echo "Note: this system is not the ISO; /etc/os-release is now ParishBSD’s."