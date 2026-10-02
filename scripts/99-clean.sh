#!/bin/sh
set -eu

echo "==> Stopping jails"
for j in $(jls name 2>/dev/null || true); do
	service jail stop "$j" || true
	jail -r "$j" 2>/dev/null || true
done

echo "==> Removing jail roots"
for d in /jail/*; do
	[ -d "$d" ] || continue
	chflags -R 0 "$d" 2>/dev/null || true
	rm -rf "$d"
done

echo "==> Removing jail configs"
rm -f /etc/jail.conf.d/*.conf

echo "==> Destroying ZFS datasets"
zfs list -H -o name | grep -E '^(zroot|tank)/jail' | while read ds; do
	zfs destroy -rf "$ds"
done

echo "==> Tearing down network"
ifconfig bridge0 destroy 2>/dev/null || true
for e in $(ifconfig -l | tr ' ' '\n' | grep '^epair'); do
	ifconfig "$e" destroy 2>/dev/null || true
done

echo "==> Removing overlays (only files we installed)"
# TODO: Compare tracked overlays against what's in /etc and remove only ours

echo "==> Disabling services"
sysrc -x jail_enable 2>/dev/null || true
sysrc -x parishbsd_enable 2>/dev/null || true

echo "==> Done."
