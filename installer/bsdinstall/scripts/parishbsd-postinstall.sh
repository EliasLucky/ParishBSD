#!/bin/sh
# parishbsd-postinstall.sh  runs inside the target chroot.
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

# Enable ParishBSD services.
sysrc parish_guardian_enable=YES
sysrc parishbsd_vaults_enable=YES
sysrc dbus_enable=YES
sysrc lightdm_enable=YES
sysrc pf_enable=YES
sysrc devfs_enable=YES

# Create the unprivileged guardian account if the package did not.
if ! pw usershow _parish >/dev/null 2>&1; then
    pw useradd _parish -u 900 -c "ParishBSD Guardian" -d /nonexistent \
        -s /usr/sbin/nologin
fi

# Securelevel.
sysrc -f /etc/loader.conf kern.securelevel=1

# Jail dataset permissions.
chown root:wheel /zroot/jails 2>/dev/null || true

echo "ParishBSD post-install complete."