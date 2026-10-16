#!/bin/sh
# parish-detect-installer.sh identify a file's type using magic bytes.
#
# Usage: parish-detect-installer.sh <file>
# Output: one line, "TYPE:detail"
#
# Does not trust the filename extension. Uses `file(1)` MIME type
# detection plus content inspection.
set -eu

file="$1"
[ -f "$file" ] || { echo "unknown:file-not-found"; exit 0; }

mime="$(file --mime-type -b "$file" 2>/dev/null || echo 'application/octet-stream')"
ext="$(printf '%s' "$(basename "$file")" | tr 'A-Z' 'a-z' | awk -F. '{print $NF}')"

# =====================================================================
# Recognize by MIME type
# =====================================================================

case "$mime" in
    application/x-dosexec|application/x-msdownload)
        # A PE executable. Could be installer or portable. Inspect
        # strings to decide.
        if strings -a "$file" 2>/dev/null | grep -qiE \
            'Nullsoft|Inno Setup|InstallShield|WiX Toolset|MSI Installer'; then
            echo "windows-installer:$ext"
        else
            echo "windows-exe-ambiguous:$ext"
        fi
        exit 0
        ;;

    application/x-msi|application/x-ole-storage)
        # MSI files are OLE compound documents.
        echo "windows-installer:msi"
        exit 0
        ;;

    application/x-executable|application/x-pie-executable)
        # Native ELF binary. If we get here for a downloaded file,
        # it's almost certainly a Linux binary (FreeBSD uses a
        # different ELF ABI).
        if file "$file" | grep -q 'FreeBSD'; then
            echo "freebsd-elf:standalone"
        else
            echo "linux-run-ambiguous:elf"
        fi
        exit 0
        ;;

    application/x-sharedlib)
        echo "linux-run-ambiguous:sharedlib"
        exit 0
        ;;

    application/x-archive)
        echo "unsupported-ar:static-lib"
        exit 0
        ;;

    application/zip)
        # A zip. Could be portable Windows program, portable Linux
        # program, source, or something else. Inspect contents.
        listing="$(unzip -l "$file" 2>/dev/null || true)"
        ;;

    application/x-tar)
        listing="$(tar -tf "$file" 2>/dev/null || true)"
        ;;

    application/gzip|application/x-gzip)
        # Could be tar.gz or gz of a single file.
        if tar -tzf "$file" >/dev/null 2>&1; then
            listing="$(tar -tzf "$file" 2>/dev/null || true)"
        else
            echo "archive-portable:gz-single"
            exit 0
        fi
        ;;

    application/x-xz)
        if tar -tJf "$file" >/dev/null 2>&1; then
            listing="$(tar -tJf "$file" 2>/dev/null || true)"
        else
            echo "archive-portable:xz-single"
            exit 0
        fi
        ;;

    application/x-bzip2)
        if tar -tjf "$file" >/dev/null 2>&1; then
            listing="$(tar -tjf "$file" 2>/dev/null || true)"
        else
            echo "archive-portable:bz2-single"
            exit 0
        fi
        ;;

    application/x-rar|application/vnd.rar)
        if command -v unrar >/dev/null 2>&1; then
            listing="$(unrar lb "$file" 2>/dev/null || true)"
        else
            echo "archive-unknown:rar-no-tool"
            exit 0
        fi
        ;;

    application/x-deb)
        echo "unsupported-deb:deb"
        exit 0
        ;;

    application/x-rpm|application/x-redhat-package-manager)
        echo "unsupported-rpm:rpm"
        exit 0
        ;;

    application/x-compress|application/x-lzma|application/x-lzip)
        echo "archive-portable:compressed-single"
        exit 0
        ;;

    text/x-shellscript)
        echo "linux-run-ambiguous:shellscript"
        exit 0
        ;;

    text/plain)
        # Fall back to extension-based guessing for shell scripts and
        # similar text files that happen to not be recognized.
        case "$ext" in
            run|bin) echo "linux-run-ambiguous:$ext"; exit 0 ;;
            sh)      echo "linux-run-ambiguous:sh"; exit 0 ;;
            *)       echo "unknown:text"; exit 0 ;;
        esac
        ;;
esac

# =====================================================================
# For archives, inspect contents to determine purpose
# =====================================================================

if [ -z "${listing:-}" ]; then
    echo "unknown:no-listing"
    exit 0
fi

# Source code signatures.
if printf '%s' "$listing" | grep -qE '(^|/)configure$'; then
    echo "source-autotools:configure"; exit 0
fi
if printf '%s' "$listing" | grep -qE '(^|/)CMakeLists\.txt$'; then
    echo "source-cmake:cmake"; exit 0
fi
if printf '%s' "$listing" | grep -qE '(^|/)meson\.build$'; then
    echo "source-meson:meson"; exit 0
fi
if printf '%s' "$listing" | grep -qE '(^|/)Makefile$'; then
    echo "source-make:makefile"; exit 0
fi

# Windows portable program: contains .exe files.
if printf '%s' "$listing" | grep -qiE '\.(exe|msi|dll)$'; then
    echo "windows-portable-archive:$ext"; exit 0
fi

# Linux portable program: has bin/ directory or *.AppImage.
if printf '%s' "$listing" | grep -qE '(^|/)(bin|usr/bin)/'; then
    echo "linux-portable-archive:$ext"; exit 0
fi
if printf '%s' "$listing" | grep -qE '\.AppImage$'; then
    echo "linux-portable-archive:appimage"; exit 0
fi

# Fallback: generic archive, no clear purpose.
echo "archive-portable:$ext"