# ParishBSD installer

**Primary:** Calamares.

**Fallback:** `bsdinstall`. Available two ways:

- **Console:** Ctrl+Alt+F2 on the live system drops to a root shell.
  Run `bsdinstall` to install to disk.
- **Desktop icon:** if X is up and Calamares exited without installing,
  the desktop shows an "Install (text mode)" launcher.

## Why Calamares is not the only path

Calamares on FreeBSD depends on `sysutils/calamares` and KPMcore; both
have historically lagged behind Linux. A volunteer must never be left
without an installer because a port broke. `bsdinstall` ships in FreeBSD
base and cannot break.

## Calamares configuration

`installer/calamares/` is copied by `iso/phases/04-config.sh` to:

- `settings.conf` → `/usr/local/etc/calamares/settings.conf`
- `branding/parishbsd/` → `/usr/local/share/calamares/branding/parishbsd/`
- `modules/unpackfs.conf` → `/usr/local/etc/calamares/modules/unpackfs.conf`

The `unpackfs` source is `/ro-root`, which `live/init.sh` bind-mounts
read-only from the uzip. This is a clean copy of the same filesystem
the user is currently running.

## Post-install

Calamares runs `/usr/local/etc/scripts/parishbsd-postinstall.sh` inside
the target chroot via the `shellprocess` module. That script creates the
`_parish` user if the package did not, enables rc services, and sets
`kern.securelevel=1` in the target's loader.conf.