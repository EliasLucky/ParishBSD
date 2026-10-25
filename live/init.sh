#!/bin/sh
# init.sh  mfsroot init. Mounts the uzip root, sets up writable tmpfs
# overlays, and hands off to the live rc or the installer.
set -eu

PATH=/sbin:/bin:/usr/sbin:/usr/bin
export PATH

msg() { echo "[parishbsd-init] $*"; }
die() { msg "FATAL: $*"; exec /bin/sh; }

# Load the modules the loader may not have loaded.
kldload geom_uzip 2>/dev/null || true
kldload tmpfs     2>/dev/null || true

# The ISO is mounted at /cdrom by the loader’s md root; find the uzip.
UZIP=""
for _candidate in /cdrom/uzip/root.uzip /uzip/root.uzip; do
    [ -f "$_candidate" ] && UZIP="$_candidate" && break
done
[ -n "$UZIP" ] || die "root.uzip not found"

MD=$(mdconfig -a -t vnode -f "$UZIP") || die "mdconfig failed"
mount -t cd9660 -o ro "/dev/$MD" / || die "mount uzip root failed"

# Writable overlays.
mount -t tmpfs tmpfs /tmp  || die "tmpfs /tmp failed"
mount -t tmpfs tmpfs /var  || die "tmpfs /var failed"
mount -t tmpfs tmpfs /root || die "tmpfs /root failed"

# /etc must be writable for live configuration; copy from the ro root.
mkdir -p /etc.live
cp -R /etc/. /etc.live/ 2>/dev/null || true
mount -t tmpfs tmpfs /etc || die "tmpfs /etc failed"
cp -R /etc.live/. /etc/ 2>/dev/null || true

# Installer trigger.
if [ -f /etc/installer ]; then
    msg "starting installer"
    exec /usr/sbin/bsdinstall
fi

msg "starting live environment"
exec /etc/rc.livecd