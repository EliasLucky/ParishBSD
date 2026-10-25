#!/bin/sh
# init.sh  mfsroot init. Mounts the uzip root, sets up writable tmpfs
# overlays, and hands off to the live rc or the installer.
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

msg() { echo "[parishbsd-init] $*"; }
die() { msg "FATAL: $*"; exec /bin/sh; }

kldload geom_uzip 2>/dev/null || true
kldload tmpfs     2>/dev/null || true

UZIP=""
for _candidate in /cdrom/uzip/root.uzip /uzip/root.uzip; do
    [ -f "$_candidate" ] && UZIP="$_candidate" && break
done
[ -n "$UZIP" ] || die "root.uzip not found"

MD=$(mdconfig -a -t vnode -f "$UZIP") || die "mdconfig failed"

# Two read-only mounts of the same image:
#   /       — with tmpfs overlays below, this is the running system
#   /ro-root— clean source for the installer's unpackfs
mkdir -p /ro-root
mount -t cd9660 -o ro "/dev/$MD" /ro-root || die "mount /ro-root failed"
mount -t cd9660 -o ro "/dev/$MD" /        || die "mount / failed"

# Writable overlays.
mount -t tmpfs tmpfs /tmp  || die "tmpfs /tmp failed"
mount -t tmpfs tmpfs /var  || die "tmpfs /var failed"
mount -t tmpfs tmpfs /root || die "tmpfs /root failed"

mkdir -p /etc.live
cp -R /etc/. /etc.live/ 2>/dev/null || true
mount -t tmpfs tmpfs /etc || die "tmpfs /etc failed"
cp -R /etc.live/. /etc/ 2>/dev/null || true

# Live user for XFCE autologin.
if ! pw usershow live >/dev/null 2>&1; then
    pw useradd live -u 1000 -c "Live User" -d /home/live -s /bin/sh -m
    echo "live:live" | pw usermod live -h 0 2>/dev/null || true
fi

msg "starting live environment"
exec /etc/rc.livecd