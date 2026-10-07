#!/bin/sh
# vault-idle-check.sh  one iteration of the vault idle-lock check.
#
# Invoked by cron every minute (see /etc/crontab). Safe to run manually.
# Reads /usr/local/etc/parishbsd/idle-lock.conf and
# /usr/local/etc/parishbsd/lock-schedules.
set -eu

CONFIG="/usr/local/etc/parishbsd/idle-lock.conf"
SCRIPTS="${PARISHBSD_ROOT:-/usr/local/parishbsd}/scripts"
STATE_DIR="/var/run/parishbsd/vault-idle"
SCHEDULES="/usr/local/etc/parishbsd/lock-schedules"

IDLE_TIMEOUT=900
INTERVAL=60
ENABLED=yes
[ -f "$CONFIG" ] && . "$CONFIG"

[ "$ENABLED" = "yes" ] || exit 0

mkdir -p "$STATE_DIR"

list_unlocked() {
	zfs list -H -o name -r zroot/vault-data 2>/dev/null | \
		grep -v '^zroot/vault-data$' | while read -r ds; do
			[ "$(zfs get -H -o value keystatus "$ds" 2>/dev/null)" = "available" ] && basename "$ds"
		done
}

is_active() {
	n="$1"
	jls name 2>/dev/null | grep -qx "$n" || return 1
	jexec "$n" ps -axo comm= 2>/dev/null | \
		grep -qE '^(sh|bash|zsh|tcsh|ksh|csh)$' && return 0
	jexec "$n" netstat -an 2>/dev/null | \
		awk '$6=="ESTABLISHED"{f=1} END{exit !f}' && return 0
	return 1
}

lock_vault() {
	n="$1"; why="$2"
	logger -t parishbsd-vault-idle "locking '$n' ($why)"
	sh "$SCRIPTS/28-lock-vault.sh" "$n" >/dev/null 2>&1 || \
		logger -t parishbsd-vault-idle "WARN: failed to lock '$n'"
	rm -f "$STATE_DIR/$n"
}

# --- Scheduled locks ---
if [ -f "$SCHEDULES" ]; then
	now="$(date +%H:%M)"
	while read -r vault at rest; do
		case "$vault" in ''|\#*) continue ;; esac
		[ "$at" = "$now" ] || continue
		[ "$(zfs get -H -o value keystatus "zroot/vault-data/$vault" 2>/dev/null)" = "available" ] || continue
		marker="$STATE_DIR/$vault.schedule"
		[ "$(cat "$marker" 2>/dev/null)" = "$now" ] && continue
		echo "$now" > "$marker"
		lock_vault "$vault" "scheduled at $now"
	done < "$SCHEDULES"
fi

# --- Idle check ---
for n in $(list_unlocked); do
	if is_active "$n"; then
		echo 0 > "$STATE_DIR/$n"
	else
		c=0
		[ -f "$STATE_DIR/$n" ] && c="$(cat "$STATE_DIR/$n")"
		c=$((c + INTERVAL))
		echo "$c" > "$STATE_DIR/$n"
		[ "$c" -ge "$IDLE_TIMEOUT" ] && lock_vault "$n" "idle for ${IDLE_TIMEOUT}s"
	fi
done
