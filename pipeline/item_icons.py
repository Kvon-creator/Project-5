#!/usr/bin/env python3
"""Paint the item and power-up drops into game sprites.

    python pipeline/item_icons.py [path/to/godot]

Each drop is a painted medallion: the SHAPE and RIM say what kind of item it
is, the GLYPH says which one. That way two drops never look alike, and the
player can still tell at a glance whether a drop is a life, an ability or an
attack upgrade before they can read the glyph.

    life        round seal, Ember rim         (extra lives)
    consumable  small round seal, Blood Rust  (healing)
    ability     diamond, Gilt rim             (new abilities on Space / E)
    attack      hexagon, Nib Teal rim         (changes to the knight's shots)

The glyphs are game-icons.net icons (CC BY 3.0, authors in CREDITS.md), kept
as SVG in docs/reference/items/. Godot rasterises them
(pipeline/rasterize_svg.gd), so no SVG library is needed here. Needs Pillow
and numpy.

Writes assets/sprites/items/<id>.png (64 x 64, the pickup) and
<id>_hud.png (32 x 32, the HUD row), plus inkling_familiar.png, the imp
itself as a creature rather than a medallion. The item ids must match
scripts/Items.gd.
"""
import os
import re
import subprocess
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "docs", "reference", "items")
OUT = os.path.join(ROOT, "assets", "sprites", "items")
DEFAULT_GODOT = r"C:\Users\kvong\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"

# id -> (icon file in docs/reference/items, category). Same ids as Items.gd.
ITEMS = {
    "phoenix_seal":   ("heart-wings.svg",        "life"),
    "ink_heart":      ("health-potion.svg",      "consumable"),
    "shadow_step":    ("sprint.svg",             "ability"),
    "warding_pages":  ("book-aura.svg",          "ability"),
    "inkling":        ("imp.svg",                "ability"),
    "blot_bomb":      ("rolling-bomb.svg",       "ability"),
    "split_nib":      ("split-arrows.svg",       "attack"),
    "bodkin_nib":     ("arrowhead.svg",          "attack"),
    "seeking_ink":    ("eye-target.svg",         "attack"),
    "mirror_ink":     ("ricochet.svg",           "attack"),
    "ember_ink":      ("fluffy-flame.svg",       "attack"),
    "storm_quill":    ("lightning-branches.svg", "attack"),
    "quickened_hand": ("hourglass.svg",          "attack"),
    "leaden_nib":     ("anvil.svg",              "attack"),
}

# The GDD palette (scripts/Palette.gd). No Hostile Magenta: that is for enemy
# bullets only.
def hexc(h):
    return np.array([int(h[i:i + 2], 16) for i in (0, 2, 4)], dtype=np.float32)

INK_BLACK = hexc("18030A")
INK_VIOLET = hexc("3C2C39")
DEEP_PLUM = hexc("421C39")
PARCHMENT = hexc("E2C5A8")
EMBER = hexc("F06A2A")
BLOOD_RUST = hexc("8E2A2A")
GILT = hexc("C8A24E")
NIB_TEAL = hexc("35D6C4")

STYLE = {
    #             rim,        glyph tint,                      scale
    "life":       (EMBER,      PARCHMENT * 0.55 + EMBER * 0.45, 1.00),
    "consumable": (BLOOD_RUST, PARCHMENT * 0.70 + EMBER * 0.30, 0.82),
    "ability":    (GILT,       PARCHMENT * 0.75 + GILT * 0.25,  1.00),
    "attack":     (NIB_TEAL,   PARCHMENT * 0.65 + NIB_TEAL * 0.35, 1.00),
}

SS = 4            # supersampling factor
SIZE = 64         # final pickup size
WORK = SIZE * SS


def shape_polygon(category, scale):
    """The medallion outline in WORK pixels, centred."""
    c = WORK / 2
    r = WORK * 0.44 * scale
    if category in ("life", "consumable"):
        return None, (c - r, c - r, c + r, c + r)          # ellipse box
    if category == "ability":
        r *= 1.08
        return [(c, c - r), (c + r, c), (c, c + r), (c - r, c)], None
    pts = []                                               # hexagon, pointy top
    for i in range(6):
        a = np.deg2rad(-90 + 60 * i)
        pts.append((c + r * np.cos(a), c + r * np.sin(a)))
    return pts, None


def mask_for(category, scale, grow=0.0):
    """Anti-aliasing comes from the supersample; `grow` widens the shape."""
    img = Image.new("L", (WORK, WORK), 0)
    d = ImageDraw.Draw(img)
    poly, box = shape_polygon(category, scale)
    if box:
        x0, y0, x1, y1 = box
        d.ellipse((x0 - grow, y0 - grow, x1 + grow, y1 + grow), fill=255)
    else:
        c = WORK / 2
        pts = []
        for x, y in poly:
            v = np.array([x - c, y - c])
            n = np.linalg.norm(v)
            pts.append(tuple(np.array([c, c]) + v * (n + grow * 1.15) / n))
        d.polygon(pts, fill=255)
    return np.asarray(img).astype(np.float32) / 255.0


def paint(item_id, glyph_png, category):
    rim_col, glyph_col, scale = STYLE[category]
    yy, xx = np.mgrid[0:WORK, 0:WORK].astype(np.float32) / WORK

    outer = mask_for(category, scale, grow=3 * SS)        # ink outline
    rim = mask_for(category, scale, grow=0)
    inner = mask_for(category, scale, grow=-5 * SS)       # face

    # Face: dark violet, lit from the top-left (the GDD's key light).
    light = np.clip(1.0 - (xx * 0.6 + yy * 0.9), 0, 1)[..., None]
    face = INK_BLACK * (1 - light) + (INK_VIOLET * 0.6 + DEEP_PLUM * 0.4) * light * 1.25
    # Rim: the category colour, brighter top-left, darker bottom-right.
    rim_rgb = rim_col * (0.55 + 0.6 * light)

    rgb = np.zeros((WORK, WORK, 3), np.float32)
    rgb[:] = INK_BLACK
    rgb = rgb * (1 - rim[..., None]) + rim_rgb * rim[..., None]
    rgb = rgb * (1 - inner[..., None]) + face * inner[..., None]

    # The glyph, with its own ink outline, centred on the face.
    g = Image.open(glyph_png).convert("RGBA")
    gsize = int(WORK * 0.56 * scale)
    g = g.resize((gsize, gsize), Image.LANCZOS)
    ga = np.zeros((WORK, WORK), np.float32)
    off = (WORK - gsize) // 2
    ga[off:off + gsize, off:off + gsize] = np.asarray(g)[..., 3].astype(np.float32) / 255.0
    ga_outline = np.asarray(Image.fromarray((ga * 255).astype(np.uint8))
                            .filter(ImageFilter.MaxFilter(2 * SS + 1))).astype(np.float32) / 255.0
    ga_outline *= inner
    ga *= inner
    glyph_rgb = glyph_col * (0.8 + 0.35 * light)
    rgb = rgb * (1 - ga_outline[..., None]) + INK_BLACK * ga_outline[..., None]
    rgb = rgb * (1 - ga[..., None]) + glyph_rgb * ga[..., None]

    # A painted highlight arc top-left on the rim.
    hl = np.clip(1 - np.hypot(xx - 0.33, yy - 0.28) / 0.22, 0, 1) ** 2 * 0.35
    rgb += (PARCHMENT - rgb) * (hl * (rim - inner))[..., None]

    # Paint grain, the same broken-edge texture the props have.
    rng = np.random.default_rng(abs(hash(item_id)) % (2 ** 32))
    grain = rng.normal(0, 6, (WORK // SS, WORK // SS)).astype(np.float32)
    grain = np.asarray(Image.fromarray(grain).resize((WORK, WORK), Image.BILINEAR))
    rgb += grain[..., None] * outer[..., None]

    alpha = outer
    out = np.dstack([np.clip(rgb, 0, 255), alpha * 255]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    pickup = img.resize((SIZE, SIZE), Image.LANCZOS)
    hud = img.resize((SIZE // 2, SIZE // 2), Image.LANCZOS)
    return pickup, hud


def familiar_sprite(glyph_png, size=44):
    """The Inkling as a creature: the imp glyph in dark ink, rimmed in Nib
    Teal (the player's colour, so it never reads as an enemy)."""
    g = Image.open(glyph_png).convert("RGBA").resize((WORK, WORK), Image.LANCZOS)
    a = np.asarray(g)[..., 3].astype(np.float32) / 255.0
    rim = np.asarray(Image.fromarray((a * 255).astype(np.uint8))
                     .filter(ImageFilter.MaxFilter(3 * SS + 1))).astype(np.float32) / 255.0
    edge = np.asarray(Image.fromarray((rim * 255).astype(np.uint8))
                      .filter(ImageFilter.MaxFilter(SS + 1))).astype(np.float32) / 255.0
    yy, xx = np.mgrid[0:WORK, 0:WORK].astype(np.float32) / WORK
    light = np.clip(1.0 - (xx * 0.6 + yy * 0.9), 0, 1)[..., None]
    body = INK_BLACK * 0.7 + NIB_TEAL * 0.12 + INK_VIOLET * 0.4 * light
    rgb = np.zeros((WORK, WORK, 3), np.float32)
    rgb[:] = INK_BLACK
    rgb = rgb * (1 - rim[..., None]) + NIB_TEAL * (0.55 + 0.5 * light) * rim[..., None]
    rgb = rgb * (1 - a[..., None]) + body * a[..., None]
    out = np.dstack([np.clip(rgb, 0, 255), edge * 255]).astype(np.uint8)
    return Image.fromarray(out, "RGBA").resize((size, size), Image.LANCZOS)


def rasterise(godot, svgs, out_dir):
    """Strip each icon's black background square and let Godot render it."""
    stripped = []
    tmp = os.path.join(out_dir, "svg")
    os.makedirs(tmp, exist_ok=True)
    for name in svgs:
        text = open(os.path.join(SRC, name), encoding="utf-8").read()
        text = re.sub(r'<path d="M0 0h512v512H0z"\s*/>', "", text, count=1)
        p = os.path.join(tmp, name)
        open(p, "w", encoding="utf-8").write(text)
        stripped.append(p)
    subprocess.run([godot, "--headless", "--path", ROOT, "--script",
                    "res://pipeline/rasterize_svg.gd", "--",
                    str(WORK), out_dir] + stripped, check=True,
                   stdout=subprocess.DEVNULL)


def main():
    godot = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_GODOT
    os.makedirs(OUT, exist_ok=True)
    work = tempfile.mkdtemp(prefix="item_glyphs_")
    svgs = sorted({icon for icon, _ in ITEMS.values()})
    rasterise(godot, svgs, work)
    for item_id, (icon, category) in ITEMS.items():
        glyph = os.path.join(work, os.path.splitext(icon)[0] + ".png")
        pickup, hud = paint(item_id, glyph, category)
        pickup.save(os.path.join(OUT, item_id + ".png"))
        hud.save(os.path.join(OUT, item_id + "_hud.png"))
        print(f"  {item_id:15s} {category:10s} <- {icon}")
    familiar_sprite(os.path.join(work, "imp.png")).save(os.path.join(OUT, "inkling_familiar.png"))
    sheet = Image.new("RGBA", (len(ITEMS) * 72 + 8, 80), (24, 3, 10, 255))
    for i, item_id in enumerate(ITEMS):
        sheet.alpha_composite(Image.open(os.path.join(OUT, item_id + ".png")), (8 + i * 72, 8))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    sheet.save(os.path.join(ROOT, "build", "items_sheet.png"))


if __name__ == "__main__":
    main()
