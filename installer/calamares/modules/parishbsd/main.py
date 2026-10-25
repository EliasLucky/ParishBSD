# ParishBSD Calamares module post-install hooks.
# v1.1: create _parish, enable guardian, set securelevel.
import libcalamares

def run():
    libcalamares.utils.target_env_call([
        "/usr/local/etc/scripts/parishbsd-postinstall.sh"
    ])
    return None