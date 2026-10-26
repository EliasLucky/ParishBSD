#!/usr/bin/env python3
"""
generate-calamares-qss.py  build a Calamares QSS from a GTK theme's
palette. Reads the theme's gtk.css (and any files it @imports), extracts
@define-color values (resolving references and shade/mix/alpha), then
substitutes them into a QSS template.

Usage:
    generate-calamares-qss.py \\
        --theme-dir /path/to/Aerobird-Twilight \\
        --template stylesheet.qss.in \\
        --output stylesheet.qss \\
        --runtime-prefix /usr/local

Exit codes:
    0  success
    1  input missing or unreadable
    2  template missing
    3  theme directory has no gtk.css
"""

import argparse
import colorsys
import re
import sys
from pathlib import Path

# ---- color parsing -------------------------------------------------------

NAMED = {
    'white': (1.0, 1.0, 1.0, 1.0),
    'black': (0.0, 0.0, 0.0, 1.0),
    'transparent': (0.0, 0.0, 0.0, 0.0),
}

def parse_color(value):
    v = value.strip()
    m = re.fullmatch(r'#([0-9a-fA-F]{6})', v)
    if m:
        return tuple(int(m.group(1)[i:i+2], 16) / 255.0 for i in (0, 2, 4)) + (1.0,)
    m = re.fullmatch(r'#([0-9a-fA-F]{8})', v)
    if m:
        s = m.group(1)
        return tuple(int(s[i:i+2], 16) / 255.0 for i in (0, 2, 4, 6))
    m = re.fullmatch(r'#([0-9a-fA-F]{3})', v)
    if m:
        s = m.group(1)
        return tuple(int(s[i]*2, 16) / 255.0 for i in range(3)) + (1.0,)
    m = re.fullmatch(r'rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+))?\s*\)', v)
    if m:
        r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
        a = float(m.group(4)) if m.group(4) else 1.0
        return (r/255.0, g/255.0, b/255.0, a)
    if v.lower() in NAMED:
        return NAMED[v.lower()]
    raise ValueError(f'cannot parse color: {value!r}')

def color_to_hex(c):
    r, g, b, a = c
    r = max(0, min(255, round(r * 255)))
    g = max(0, min(255, round(g * 255)))
    b = max(0, min(255, round(b * 255)))
    a = max(0, min(255, round(a * 255)))
    if a == 255:
        return f'#{r:02x}{g:02x}{b:02x}'
    return f'#{r:02x}{g:02x}{b:02x}{a:02x}'

def shade_color(c, factor):
    r, g, b, a = c
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    l = max(0.0, min(1.0, l * factor))
    r, g, b = colorsys.hls_to_rgb(h, l, s)
    return (r, g, b, a)

def mix_colors(c1, c2, factor):
    return tuple(c1[i] * factor + c2[i] * (1 - factor) for i in range(4))

# ---- GTK CSS parsing ----------------------------------------------------

def read_file(p):
    with open(p, 'r', encoding='utf-8', errors='replace') as f:
        return f.read()

IMPORT_RE = re.compile(
    r'@import\s+(?:url\(\s*["\']?([^)"\']+)["\']?\s*\)|["\']([^"\']+)["\'])\s*;'
)

def inline_imports(css, base_dir, depth=0):
    """Recursively inline @import statements. Drops remote imports."""
    if depth > 20:
        return css
    def repl(m):
        path = m.group(1) or m.group(2)
        if path.startswith(('http://', 'https://', '//', 'data:')):
            return ''
        full = (base_dir / path).resolve()
        if not full.exists():
            return ''
        try:
            inner = read_file(full)
        except OSError:
            return ''
        return inline_imports(inner, full.parent, depth + 1)
    return IMPORT_RE.sub(repl, css)

DEFINE_COLOR_RE = re.compile(r'@define-color\s+([\w-]+)\s+([^;]+);')

def resolve_expr(value, palette):
    value = value.strip()

    # GTK names use hyphens; our palette keys use underscores.
    def sub_ref(m):
        name = m.group(1).replace('-', '_')
        if name in palette:
            return palette[name]
        return palette.get(m.group(1), m.group(0))

    value = re.sub(r'@([\w-]+)', sub_ref, value)

    def do_shade(m):
        try:
            c = parse_color(m.group(1).strip())
            return color_to_hex(shade_color(c, float(m.group(2))))
        except (ValueError, TypeError):
            return m.group(0)
    value = re.sub(r'shade\(\s*([^,()]+?)\s*,\s*([\d.]+)\s*\)', do_shade, value)

    def do_lighter(m):
        try:
            return color_to_hex(shade_color(parse_color(m.group(1).strip()), 1.3))
        except (ValueError, TypeError):
            return m.group(0)
    value = re.sub(r'lighter\(\s*([^()]+?)\s*\)', do_lighter, value)

    def do_darker(m):
        try:
            return color_to_hex(shade_color(parse_color(m.group(1).strip()), 0.7))
        except (ValueError, TypeError):
            return m.group(0)
    value = re.sub(r'darker\(\s*([^()]+?)\s*\)', do_darker, value)

    def do_mix(m):
        try:
            c1 = parse_color(m.group(1).strip())
            c2 = parse_color(m.group(2).strip())
            return color_to_hex(mix_colors(c1, c2, float(m.group(3))))
        except (ValueError, TypeError):
            return m.group(0)
    value = re.sub(r'mix\(\s*([^,()]+?)\s*,\s*([^,()]+?)\s*,\s*([\d.]+)\s*\)', do_mix, value)

    def do_alpha(m):
        try:
            c = parse_color(m.group(1).strip())
            return color_to_hex((c[0], c[1], c[2], float(m.group(2))))
        except (ValueError, TypeError):
            return m.group(0)
    value = re.sub(r'alpha\(\s*([^,()]+?)\s*,\s*([\d.]+)\s*\)', do_alpha, value)

    return value.strip()

def build_palette(css):
    raw = {}
    for m in DEFINE_COLOR_RE.finditer(css):
        name = m.group(1).replace('-', '_')
        raw[name] = m.group(2).strip()

    palette = dict(raw)
    for _ in range(50):
        changed = False
        for name, value in list(palette.items()):
            new_value = resolve_expr(value, palette)
            if new_value != value:
                palette[name] = new_value
                changed = True
        if not changed:
            break

    result = {}
    for name, value in palette.items():
        v = value.strip()
        if re.fullmatch(r'#[0-9a-fA-F]{3,8}', v) or re.fullmatch(r'rgba?\([^)]+\)', v):
            result[name] = v
    return result

# ---- template rendering -------------------------------------------------

PLACEHOLDER_RE = re.compile(r'@@([\w_]+)@@')

# Defaults from Aerobird's colors.css + colors-themed.css.
# Used when the theme does not define a name we reference.
DEFAULTS = {
    # widgets/colors.css  semantic GTK palette
    'theme_bg_color':            '#e8ecf6',
    'theme_fg_color':            '#000000',
    'theme_base_color':          '#ffffff',
    'theme_text_color':          '#000000',
    'theme_selected_bg_color':   '#3399ff',
    'theme_selected_fg_color':   '#ffffff',
    'theme_unfocused_bg_color':  '#e8ecf6',
    'theme_unfocused_fg_color':  '#74767b',
    'insensitive_bg_color':      '#f1f4fa',
    'insensitive_fg_color':      '#74767b',
    'borders':                   '#707070',
    'unfocused_borders':         '#707070',
    'warning_color':             '#f57900',
    'error_color':               '#cc0000',
    'success_color':             '#33d17a',

    # widgets/colors-themed.css  Aero palette
    'aero_base':                 '#396cb6',
    'aero_dark':                 '#3b64a0',
    'aero_light':                '#9cb5da',
    'aero_glow':                 '#3fcef2',
    'aero_outline':              '#343434',
    'aero_base_i':               '#b4c1d5',
    'aero_dark_i':               '#6b8bbb',
    'aero_light_i':              '#ffffff',

    # Derived: mix(@aero-light, @aero-base, 0.60) from the headerbar.
    # Pre-computed because mix() at that ratio is not easily expressible
    # in QSS.
    'aero_mid':                  '#72a1c6',
}

def render(template, palette, theme_root):
    lookup = dict(DEFAULTS)
    lookup.update(palette)
    lookup['theme_root'] = theme_root

    def sub(m):
        name = m.group(1)
        if name in lookup:
            return lookup[name]
        sys.stderr.write(f'warning: no value for @@{name}@@; leaving as-is\n')
        return m.group(0)

    return PLACEHOLDER_RE.sub(sub, template)

# ---- main ---------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--theme-dir', required=True)
    ap.add_argument('--template',  required=True)
    ap.add_argument('--output',    required=True)
    ap.add_argument('--runtime-prefix', default='/usr/local')
    args = ap.parse_args()

    theme_dir = Path(args.theme_dir)
    if not theme_dir.is_dir():
        sys.stderr.write(f'error: theme dir missing: {theme_dir}\n')
        return 1

    gtk_css = theme_dir / 'gtk.css'
    if not gtk_css.exists():
        sys.stderr.write(f'error: {gtk_css} not found\n')
        return 3

    template_path = Path(args.template)
    if not template_path.exists():
        sys.stderr.write(f'error: template missing: {template_path}\n')
        return 2

    css = inline_imports(read_file(gtk_css), theme_dir)
    palette = build_palette(css)

    runtime_theme_root = f'{args.runtime_prefix}/share/themes/{theme_dir.name}'
    output = render(read_file(template_path), palette, runtime_theme_root)

    Path(args.output).write_text(output, encoding='utf-8')
    sys.stderr.write(
        f'wrote {args.output}: {len(palette)} palette colors, {len(output)} bytes\n'
    )
    return 0

if __name__ == '__main__':
    sys.exit(main())
