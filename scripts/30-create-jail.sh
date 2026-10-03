#!/bin/sh
# Create a jail root and install its config. Usage: 30-create-jail.sh <name>
set -eu

name ="${1:?usage: 30-create-jail.sh <name>}"
tier="${2:-app}"
jailroot="/usr/local/jails/$tier/$name"
version="$(freebsd-version -u)"
arch="$(uname -m)"

case "$name" in
	vault*) tier=vault ;;
esac

if [ ! -d "$jailroot" ]; then
	echo "Creating jail root at $jailroot"
	mkdir -p "$jailroot"
	fetch -o /tmp/base.txz \ "https://download.freebsd.org/releases/$arch/$version/base.txz"
	tar -xpf /tmp/base.txz -C "$jailrot"
	rm /tmp/base/.txz
fi

cfg="host/etc/jail.conf.d/$name.conf"
if [ -f "$cfg" ]; then
	install -m 0644 "$cfg" "/etc/jail.conf.d/$name.conf"
else
	echo "No jail config for $name in repo - skipping."
fi
