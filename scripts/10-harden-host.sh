#!/bin/sh
# Disable all unnecessary network services on the host.
set -eu

sysrc sendmail_enable=NONE
sysrc sendmail_submit_enable=NO
sysrc sendmail_outbound_enable=NO
sysrc sendmail_msp_queue_enable=NO
sysrc sshd_enable=NO
sysrc ntpd_enable=NO
sysrc inetd_enable=NO 2>/dev/null || true

for s in sendmail sshd ntpd inetd; do
	service "$s" onestop 2>/dev/null || true
done
