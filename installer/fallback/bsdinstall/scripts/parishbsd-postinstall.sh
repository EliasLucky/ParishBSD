#!/bin/sh
# parishbsd-postinstall.sh  runs inside the target chroot during install.
# Called by either:
#   - Calamares' shellprocess module (installer/calamares/modules/shellprocess.conf)
#   - bsdinstall's BSDINSTALL_CHROOT_POSTINSTALL (installer/fallback/bsdinstall/installerconfig)
set -eu
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin
export PATH

# ---- enable ParishBSD services -------------------------------------------
sysrc parish_guardian_enable=YES
sysrc parishbsd_vaults_enable=YES
sysrc dbus_enable=YES
sysrc lightdm_enable=YES
sysrc pf_enable=YES
sysrc devfs_enable=YES

# ---- unprivileged guardian account ---------------------------------------
if ! pw usershow _parish >/dev/null 2>&1; then
    pw useradd _parish -u 900 \
        -c "ParishBSD Guardian" \
        -d /nonexistent \
        -s /usr/sbin/nologin
fi

# ---- securelevel in the target's loader.conf -----------------------------
# Written directly rather than via sysrc -f because loader.conf may not
# exist yet on a minimal install.
LOADER_CONF=/boot/loader.conf
touch "$LOADER_CONF"
if ! grep -q '^kern.securelevel=' "$LOADER_CONF"; then
    echo 'kern.securelevel=1' >> "$LOADER_CONF"
fi

# ---- jail dataset layout -------------------------------------------------
mkdir -p /usr/local/jails/app /usr/local/jails/vault /usr/local/jails/containers
chown root:wheel /usr/local/jails 2>/dev/null || true

# ---- apply the artwork theme and wallpaper to the installed system -------
# This writes /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/*.xml so that the
# first user created by the installer inherits Aerobird-Twilight and the
# ParishBSD wallpaper on their first login.
#
# The script is installed by iso/phases/04-config.sh into /usr/local/bin/.
# It reads the .template/ directory and writes the real files.
if [ -x /usr/local/bin/parishbsd-theme-detect ]; then
    /usr/local/bin/parishbsd-theme-detect --root / || \
        echo "parishbsd-postinstall: theme detection failed; using XFCE defaults" >&2
else
    echo "parishbsd-postinstall: parishbsd-theme-detect missing; skipping theme setup" >&2
fi

# ---- ensure the .template/ directory is not visible to end users --------
# It contains no secrets; hiding it prevents accidental edits.
if [ -d /etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template ]; then
    chmod 0700 /etc/xdg/xfce4/xfconf/xfce-perchannel-xml.template 2>/dev/null || true
fi

echo "ParishBSD post-install complete."