#!/bin/sh
set -eu

echo "==> Stopping jails"
for j in $(jls name 2>/dev/null || true); do
	service jail onestop "$j" 2>/dev/null || true
	jail -r "$j" 2>/dev/null || true
done

echo "==> Removing jail roots"
for d in /usr/local/jails/app/* /usr/local/jails/vault/*; do
	[ -d "$d" ] || continue
	chflags -R 0 "$d" 2>/dev/null || true
	rm -rf "$d"
done

echo "==> Removing jail configs"
rm -f /etc/jail.conf.d/*.conf
rm -f /etc/rc.conf.d/parishbsd
pfctl -d 2>/dev/null || true
ifconfig bridge0 destroy 2>/dev/null || true

#echo "==> Destroying ZFS datasets"
#zfs list -H -o name | grep -E '^(zroot|tank)/jail' | while read ds; do
#	zfs destroy -rf "$ds"
#done
