#!/bin/sh
# Create a jail root and install its config. Usage: 30-create-jail.sh <name>
set -eu

name="${1:?usage: 30-create-jail.sh <name>}"
tier="${2:-app}"
jailroot="/usr/local/jails/$tier/$name"
version="$(freebsd-version -u | sed 's/-p[0-9]*$s//')"
arch="$(uname -m)"

case "$name" in
	vault*) tier=vault ;;
esac

if [ ! -d "$jailroot" ]; then
	echo "Creating jail root at $jailroot"
	mkdir -p "$jailroot"
	fetch -o /tmp/base.txz "https://download.freebsd.org/releases/$arch/$version/base.txz"
	tar -xpf /tmp/base.txz -C "$jailrot"
	rm /tmp/base/.txz
else
	echo "jail root $jailroot already exists - leaving it alone"
fi

cfg="$(dirname "$0")/../host/etc/jail.conf.d/$name.conf"
if [ -f "$cfg" ]; then
	install -d /etc/jail.conf.d
	install -m 0644 "$cfg" "/etc/jail.conf.d/$name.conf"
	echo "Installed /etc/jail.conf.d/$name.conf"
else
	echo "No jail config for $name in repo - skipping config install."
fi
