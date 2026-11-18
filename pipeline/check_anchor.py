#!/usr/bin/env python3
"""
Measure rendered sprites against the anchor asset.

GDD, Anchor asset:
    Every other asset is checked against it for scale, outline weight, light
    direction and palette before it goes in the game.

This makes that check a command instead of an eyeball. It reports, per sprite:

  frame      the PNG's pixel size (should be 128 x 128 for characters)
  content    the bounding box of non-transparent pixels
  height     content height in px - the number the anchor spec is about
  centre     where the content sits in the frame, so sprites do not drift
  palette    the most common opaque colours, checked against the GDD table

Runs on plain Python 3, no dependencies: it inflates the PNG and undoes the
scanline filters by hand.

    python3 pipeline/check_anchor.py                  # everything
    python3 pipeline/check_anchor.py assets/sprites/player/player_idle_SE.png
"""

import glob
import os
import struct
import sys
import zlib

# --------------------------------------------------------------------------
# GDD palette, for the palette check
# --------------------------------------------------------------------------

PALETTE = {
    # Kept in step with scripts/Palette.gd and pipeline/rig_common.py -
    # the MEASURED palette from docs/reference, not the original GDD table.
    "35D6C4": "Nib Teal (player shots/pickup)",
    "FF2E6E": "Hostile Magenta (enemy bullets ONLY)",
    "F06A2A": "Ember (plume/flame/barrel)",
    "FFC93C": "Graze Gold (meter/sparks)",
    "E2C5A8": "Parchment (paper/cape/UI)",
    "BE9E91": "Candle Warm (lit stone)",
    "8A8088": "Stone Lit (floor)",
    "776B70": "Stone Mid (walls)",
    "554F59": "Stone Shadow",
    "3C2C39": "Ink Violet (deep shadow)",
    "18030A": "Ink Black (pools/outlines)",
    "C8A24E": "Gilt (vine work)",
    "886181": "Creature Violet (enemy flesh)",
    "BA7977": "Creature Rust (enemy hide)",
    "421C39": "Deep Plum (enemy shadow)",
    "868178": "Steel (hero armour)",
    "8E2A2A": "Blood Rust (traps/damage)",
}

# The anchor spec: "about 64 px tall in a 128 x 128 frame".
ANCHOR_TARGET_PX = 64
ANCHOR_TOLERANCE_PX = 6   # "about" - a few px either way is fine
ANCHOR_FRAME_PX = 128


# --------------------------------------------------------------------------
# Minimal PNG reader
# --------------------------------------------------------------------------

def read_png(path):
    """Return (width, height, pixels) where pixels is a list of RGBA tuples."""
    with open(path, "rb") as fh:
        data = fh.read()

    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path}: not a PNG")

    pos = 8
    width = height = bit_depth = colour_type = None
    idat = bytearray()
    palette = None
    trns = None

    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        ctype = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length  # 4 len + 4 type + body + 4 crc

        if ctype == b"IHDR":
            width, height, bit_depth, colour_type = struct.unpack(
                ">IIBB", body[:10])
        elif ctype == b"PLTE":
            palette = [tuple(body[i:i + 3]) for i in range(0, len(body), 3)]
        elif ctype == b"tRNS":
            trns = body
        elif ctype == b"IDAT":
            idat += body
        elif ctype == b"IEND":
            break

    if bit_depth != 8:
        raise ValueError(f"{path}: only 8-bit PNGs supported "
                         f"(got {bit_depth})")

    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[colour_type]
    raw = zlib.decompress(bytes(idat))
    stride = width * channels

    # Undo the per-scanline filters. Each row starts with a filter byte.
    out = bytearray(stride * height)
    prev = bytearray(stride)
    src = 0
    for y in range(height):
        ftype = raw[src]
        src += 1
        line = bytearray(raw[src:src + stride])
        src += stride

        if ftype == 1:      # Sub
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 0xFF
        elif ftype == 2:    # Up
            for i in range(stride):
                line[i] = (line[i] + prev[i]) & 0xFF
        elif ftype == 3:    # Average
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:    # Paeth
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                b = prev[i]
                c = prev[i - channels] if i >= channels else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                line[i] = (line[i] + pred) & 0xFF
        elif ftype != 0:
            raise ValueError(f"{path}: bad filter type {ftype}")

        out[y * stride:(y + 1) * stride] = line
        prev = line

    pixels = []
    for i in range(0, len(out), channels):
        px = out[i:i + channels]
        if colour_type == 6:
            pixels.append((px[0], px[1], px[2], px[3]))
        elif colour_type == 2:
            pixels.append((px[0], px[1], px[2], 255))
        elif colour_type == 4:
            pixels.append((px[0], px[0], px[0], px[1]))
        elif colour_type == 0:
            pixels.append((px[0], px[0], px[0], 255))
        elif colour_type == 3:
            rgb = palette[px[0]]
            alpha = trns[px[0]] if trns and px[0] < len(trns) else 255
            pixels.append(rgb + (alpha,))

    return width, height, pixels


# --------------------------------------------------------------------------
# Measurements
# --------------------------------------------------------------------------

ALPHA_FLOOR = 16   # treat near-transparent AA fringe as empty


def content_bbox(width, height, pixels):
    """Bounding box of opaque content, as (x0, y0, x1, y1) inclusive."""
    x0, y0, x1, y1 = width, height, -1, -1
    for y in range(height):
        row = y * width
        for x in range(width):
            if pixels[row + x][3] > ALPHA_FLOOR:
                if x < x0:
                    x0 = x
                if x > x1:
                    x1 = x
                if y < y0:
                    y0 = y
                if y > y1:
                    y1 = y
    if x1 < 0:
        return None
    return x0, y0, x1, y1


def _hex_rgb(hexstr):
    return (int(hexstr[0:2], 16), int(hexstr[2:4], 16), int(hexstr[4:6], 16))


ABYSS_RGB = _hex_rgb("120E1A")
BONE_RGB = _hex_rgb("D8C8A8")


def nearest_swatch(rgb):
    """
    Closest point on the palette, as (swatch_hex, distance).

    Not a plain nearest-swatch test. The cel shader deliberately produces a
    shadow band (base mixed toward Abyss) and a highlight band (base mixed
    toward Bone) for every material, so a correct pixel is usually NOT equal
    to any swatch. Measuring against the swatches alone flags all of that
    legitimate shading as drift.

    So each swatch is treated as a short ramp from its shadow through the
    swatch to its highlight, and a pixel is scored against the nearest point
    on the nearest ramp. A pixel that is genuinely off-palette - a grey, or a
    stray hue - still scores far from every ramp.
    """
    best, best_d = None, None
    for hexstr in PALETTE:
        base = _hex_rgb(hexstr)
        shadow = tuple(base[i] + (ABYSS_RGB[i] - base[i]) * 0.6
                       for i in range(3))
        light = tuple(base[i] + (BONE_RGB[i] - base[i]) * 0.35
                      for i in range(3))
        for a, b in ((shadow, base), (base, light)):
            d = _dist_to_segment(rgb, a, b)
            if best_d is None or d < best_d:
                best, best_d = hexstr, d
    return best, best_d


def _dist_to_segment(p, a, b):
    """Squared distance from point p to the segment ab, in RGB space."""
    ab = [b[i] - a[i] for i in range(3)]
    ap = [p[i] - a[i] for i in range(3)]
    denom = sum(c * c for c in ab)
    if denom == 0:
        return sum(c * c for c in ap)
    t = sum(ap[i] * ab[i] for i in range(3)) / denom
    t = max(0.0, min(1.0, t))
    return sum((ap[i] - t * ab[i]) ** 2 for i in range(3))


def top_colours(pixels, limit=6):
    """
    The dominant opaque colours, as true means rather than bucket centres.

    Anti-aliasing splits one flat cel band into dozens of near-identical
    values, so pixels are bucketed to group them. But reporting the bucket
    CENTRE throws the hue away - a violet-grey like #6C616A bucketed to 16
    levels reads back as a flat #666666, which looks like an off-palette grey
    when the pixel was fine. So buckets are coarse enough to group, while the
    reported colour is the average of the real pixels in the bucket.
    """
    buckets = {}
    for r, g, b, a in pixels:
        if a <= 200:
            continue
        key = (r >> 3, g >> 3, b >> 3)   # 32 levels per channel
        acc = buckets.get(key)
        if acc is None:
            buckets[key] = [r, g, b, 1]
        else:
            acc[0] += r
            acc[1] += g
            acc[2] += b
            acc[3] += 1

    ranked = sorted(buckets.values(), key=lambda acc: -acc[3])[:limit]
    total = sum(acc[3] for acc in buckets.values()) or 1
    out = []
    for sr, sg, sb, n in ranked:
        rgb = (int(round(sr / n)), int(round(sg / n)), int(round(sb / n)))
        swatch, dist = nearest_swatch(rgb)
        out.append({
            "hex": "%02X%02X%02X" % rgb,
            "share": n / total,
            "swatch": swatch,
            "dist": dist ** 0.5,
        })
    return out


def check(path, is_anchor=False):
    width, height, pixels = read_png(path)
    bbox = content_bbox(width, height, pixels)
    name = os.path.relpath(path)

    print(f"\n{name}")
    print(f"  frame      {width} x {height}")

    if bbox is None:
        print("  content    EMPTY - nothing opaque rendered")
        return False

    x0, y0, x1, y1 = bbox
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    cx = (x0 + x1) / 2.0
    print(f"  content    x {x0}-{x1}  y {y0}-{y1}   ({cw} x {ch} px)")
    print(f"  centre     x {cx:.1f} (frame centre {width / 2:.1f}), "
          f"base y {y1} ({height - 1 - y1} px above frame bottom)")

    ok = True

    if is_anchor:
        print(f"  height     {ch} px   target {ANCHOR_TARGET_PX} "
              f"+/- {ANCHOR_TOLERANCE_PX}")
        if width != ANCHOR_FRAME_PX or height != ANCHOR_FRAME_PX:
            print(f"  FAIL       frame must be {ANCHOR_FRAME_PX} x "
                  f"{ANCHOR_FRAME_PX}")
            ok = False
        if abs(ch - ANCHOR_TARGET_PX) > ANCHOR_TOLERANCE_PX:
            scale = ANCHOR_TARGET_PX / float(ch)
            print(f"  FAIL       off target. Multiply FRAME_HEIGHT_M by "
                  f"{1 / scale:.4f} in pipeline/player.py")
            ok = False
        else:
            print("  OK         within anchor tolerance")

    print("  palette")
    for c in top_colours(pixels):
        flag = "" if c["dist"] < 30 else "   <-- off-palette"
        print(f"    #{c['hex']}  {c['share'] * 100:5.1f}%  "
              f"~ {PALETTE[c['swatch']]}{flag}")

    return ok


def main():
    args = sys.argv[1:]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    if args:
        targets = args
    else:
        targets = sorted(glob.glob(os.path.join(
            root, "assets", "sprites", "**", "*.png"), recursive=True))

    if not targets:
        print("No sprites found. Render some first:")
        print("  blender -b --python pipeline/player.py")
        return 1

    all_ok = True
    for path in targets:
        is_anchor = path.endswith("player_idle_anchor.png") or \
            path.endswith("player_idle_SE.png")
        try:
            if not check(path, is_anchor=is_anchor):
                all_ok = False
        except Exception as exc:  # noqa: BLE001
            print(f"\n{os.path.relpath(path)}\n  ERROR {exc}")
            all_ok = False

    print("\n" + ("All checks passed." if all_ok else "Some checks failed."))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
