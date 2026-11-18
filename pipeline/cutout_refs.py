#!/usr/bin/env python3
"""Cut the reference paintings out of their backgrounds and scale them to
game size.

This is the second sprite set, beside the Blender renders. The references in
docs/reference/ are painted on a checkerboard, on parchment, or on a flat dark
card; none of them carries real transparency. This script keys the background
out, trims, and writes game-scale PNGs to assets/sprites/refs/.

    python3 pipeline/cutout_refs.py            # everything
    python3 pipeline/cutout_refs.py --sheet    # also a contact sheet to eyeball

Keying is a flood fill from the image border through "background-like"
pixels, so the ink outline that every painting has stops the fill and the
knight's grey armour or the hare's pale face survive. Enclosed background
pockets (the hare's bow against the parchment) are removed by a second pass
that drops any large background-like pocket. Needs Pillow + numpy.
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF = os.path.join(ROOT, "docs", "reference")
OUT = os.path.join(ROOT, "assets", "sprites", "refs")
WORK_HEIGHT = 640            # key at this height, then downscale to game size

# name, source, background kind, target height in px, optional crop box
# (in source pixels) for sheets that hold several props.
JOBS = [
    ("hero",      "hero-nib-knight.png",      "checker",   84, None),
    ("snail",     "enemy-armored-snail.jpg",  "checker",   60, None),
    ("hare",      "enemy-hare-archer.jpg",    "parchment", 88, None),
    ("grotesque", "enemy-rat-demon.jpg",      "checker",  100, None),
    ("scribe",    "boss-ink-scribe.png",      "dark",     190, None),
    # props sheet (1024 x 572): two rows of cells, labels between them
    ("lamp_oil",  "props-sheet.png", "dark", 56, (20, 20, 235, 285)),
    ("tome_1",    "props-sheet.png", "dark", 52, (240, 30, 455, 285)),
    ("tome_2",    "props-sheet.png", "dark", 52, (465, 30, 715, 285)),
    ("tome_3",    "props-sheet.png", "dark", 52, (730, 30, 985, 285)),
    ("trap_1",    "props-sheet.png", "dark", 48, (20, 330, 250, 515)),
    ("trap_2",    "props-sheet.png", "dark", 48, (255, 330, 500, 515)),
    ("trap_3",    "props-sheet.png", "dark", 48, (505, 330, 780, 515)),
    ("shell",     "props-sheet.png", "dark", 50, (785, 330, 1015, 515)),
]

ROOM_JOBS = [  # painted rooms: just resize to the shared canvas
    ("room_02", "room-painted-interior.png", (1152, 640)),
    ("room_03", "room-boss-arena-pixel.png", (1152, 640)),
]


def background_mask(rgb, kind):
    """Boolean mask of pixels that look like the background."""
    r, g, b = [rgb[..., i].astype(np.int16) for i in range(3)]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    sat = mx - mn
    val = (r + g + b) // 3
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(np.int16)
    if kind == "checker":
        # Two greys. Take the darkest and lightest border greys as the range.
        greys = border[(border.max(1) - border.min(1)) < 12].mean(1)
        lo, hi = np.percentile(greys, 2) - 14, np.percentile(greys, 98) + 14
        return (sat < 20) & (val >= lo) & (val <= hi)
    if kind == "parchment":
        med = np.median(border, axis=0)
        dist = np.abs(rgb.astype(np.int16) - med).sum(-1)
        # parchment is warm, light and only mildly saturated
        return (dist < 110) & (val > 150) & (sat < 90) & (r >= g) & (g >= b)
    if kind == "dark":
        # A neutral dark card. The ink splatter on the boss is nearly as dark
        # but purple, so neutrality (low saturation) is the real test.
        med = np.median(border, axis=0)
        dist = np.abs(rgb.astype(np.int16) - med).sum(-1)
        return (dist < 96) & (sat < 16)
    raise ValueError(kind)


def flood_from_border(mask):
    """Pixels of `mask` reachable from the image border, 4-connected."""
    h, w = mask.shape
    seen = np.zeros_like(mask)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if mask[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and mask[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def drop_large_pockets(bg_like, filled, min_area):
    """Enclosed background pockets bigger than min_area also become
    transparent (the hare's bow, the gap under the snail's spear)."""
    h, w = bg_like.shape
    todo = bg_like & ~filled
    seen = np.zeros_like(todo)
    out = filled.copy()
    ys, xs = np.nonzero(todo)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        comp = [(y0, x0)]
        seen[y0, x0] = True
        q = deque(comp)
        while q:
            y, x = q.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and todo[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    comp.append((ny, nx))
                    q.append((ny, nx))
        if len(comp) >= min_area:
            for y, x in comp:
                out[y, x] = True
    return out


def keep_main_islands(alpha, min_area):
    """Drop opaque specks (checker noise) that are not part of the figure."""
    opaque = alpha > 0
    h, w = opaque.shape
    seen = np.zeros_like(opaque)
    keep = np.zeros_like(opaque)
    ys, xs = np.nonzero(opaque)
    for y0, x0 in zip(ys, xs):
        if seen[y0, x0]:
            continue
        comp = [(y0, x0)]
        seen[y0, x0] = True
        q = deque(comp)
        while q:
            y, x = q.popleft()
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < h and 0 <= nx < w and opaque[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    comp.append((ny, nx))
                    q.append((ny, nx))
        if len(comp) >= min_area:
            for y, x in comp:
                keep[y, x] = True
    return np.where(keep, alpha, 0)


def cut(name, src, kind, target_h, box):
    im = Image.open(os.path.join(REF, src)).convert("RGB")
    if box:
        im = im.crop(box)
    # work at a manageable size
    scale = WORK_HEIGHT / im.height
    if scale < 1:
        im = im.resize((round(im.width * scale), WORK_HEIGHT), Image.LANCZOS)
    rgb = np.asarray(im)
    bg = background_mask(rgb, kind)
    filled = flood_from_border(bg)
    filled = drop_large_pockets(bg, filled, min_area=int(0.004 * bg.size))
    alpha = np.where(filled, 0, 255).astype(np.uint8)
    alpha = keep_main_islands(alpha, min_area=int(0.002 * bg.size))

    # soften the cut: erode 1 px, then a light blur on the alpha only
    a_im = Image.fromarray(alpha).filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.9))
    alpha = np.asarray(a_im)

    rgba = np.dstack([rgb, alpha])
    out = Image.fromarray(rgba, "RGBA")
    bbox = out.getbbox()
    out = out.crop(bbox)

    # premultiply before the final downscale so edges don't pick up the
    # colour of transparent pixels
    arr = np.asarray(out).astype(np.float32)
    a = arr[..., 3:4] / 255.0
    pm = np.concatenate([arr[..., :3] * a, arr[..., 3:4]], -1)
    pm_im = Image.fromarray(pm.astype(np.uint8), "RGBA")
    s = target_h / pm_im.height
    small = pm_im.resize((max(1, round(pm_im.width * s)), target_h), Image.LANCZOS)
    arr = np.asarray(small).astype(np.float32)
    a = np.clip(arr[..., 3:4], 1, 255)
    un = np.concatenate([np.clip(arr[..., :3] * 255.0 / a, 0, 255), arr[..., 3:4]], -1)
    final = Image.fromarray(un.astype(np.uint8), "RGBA")
    path = os.path.join(OUT, name + ".png")
    final.save(path)
    print(f"  {name:10s} {final.width:4d} x {final.height:<4d} <- {src} ({kind})")
    return final


def repair_arena(im):
    """The boss-arena reference is a *screenshot*: it has the boss, bullets,
    a hero and a HUD painted in. Only the arena is wanted. The floor is
    concentric rings on a square tile grid around one centre, so floor can
    be cloned by mirroring across the vertical axis or rotating a quarter
    turn (both keep the tiles square), and the arena is round, so the clean
    bottom half can stand in for the top. Coordinates are for 1152 x 640.
    Measured positions: hero + teal shots x 550-717, y 333-540; boss and
    pink swirls all above y 345; boss bar y 5-49; player HUD bottom-left."""
    arr = np.asarray(im).astype(np.float32)
    h, w = arr.shape[:2]
    cx, cy = 576, 345

    def feather(y0, y1, x0, x1, edge=14):
        """A mask that is 1 inside the box and ramps to 0 over `edge` px at
        its border, so a clone has no hard seam."""
        ys = np.arange(y0, y1)[:, None].astype(np.float32)
        xs = np.arange(x0, x1)[None, :].astype(np.float32)
        ry = np.minimum(np.minimum(ys - y0 + 1, y1 - ys), edge) / edge
        rx = np.minimum(np.minimum(xs - x0 + 1, x1 - xs), edge) / edge
        return np.clip(np.minimum(ry, rx), 0, 1)[..., None]

    def paste(y0, y1, x0, x1, src):
        m = feather(y0, y1, x0, x1)
        arr[y0:y1, x0:x1] = arr[y0:y1, x0:x1] * (1 - m) + src * m

    def mirror_x(x0, y0, x1, y1):
        paste(y0, y1, x0, x1, arr[y0:y1, (w - x1):(w - x0)][:, ::-1].copy())

    def rotate_clone(x0, y0, x1, y1, angle_deg):
        a = np.deg2rad(angle_deg)
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        dx, dy = xs - cx, ys - cy
        sx = np.clip(np.rint(cx + dx * np.cos(a) - dy * np.sin(a)), 0, w - 1).astype(int)
        sy = np.clip(np.rint(cy + dx * np.sin(a) + dy * np.cos(a)), 0, h - 1).astype(int)
        paste(y0, y1, x0, x1, arr[sy, sx].copy())

    # Every region is padded ~20 px past the measured content, because the
    # feathered edge lets the original show through near a region's border.
    # 1. player HUD, bottom-left corner <- the right corner, mirrored
    mirror_x(16, 540, 210, 636)
    # 2. the teal shots, right of the axis <- the left side, mirrored. Wider
    #    on the upper rows so the pink swirl's tail (x 746-800, y ~300-330)
    #    goes too; narrower below, where the mirrored source would otherwise
    #    pick up the hero.
    mirror_x(584, 284, 810, 460)
    mirror_x(584, 440, 746, 576)
    # 3. the hero himself, on the axis <- a quarter turn to the right, which
    #    now lands entirely on the floor cleaned in step 2 (the left turn
    #    hits the central ink splash)
    rotate_clone(526, 430, 622, 566, -90)
    # 4. the boss and the swirls: clean bottom half over the top half
    n = h - cy
    arr[cy - n:cy] = arr[cy:h][::-1]
    # 5. what the mirror could not reach at the very top: continue outward
    rest = cy - n
    arr[0:rest] = arr[rest:rest * 2][::-1]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8))


def rooms():
    for name, src, size in ROOM_JOBS:
        im = Image.open(os.path.join(REF, src)).convert("RGB").resize(size, Image.LANCZOS)
        if name == "room_03":
            im = repair_arena(im)
        path = os.path.join(ROOT, "assets", "sprites", "rooms", name + ".png")
        im.save(path)
        print(f"  {name:10s} {im.width} x {im.height} <- {src}")


def contact_sheet(images):
    """All cut-outs on a stone-coloured card, at game scale, for eyeballing."""
    pad = 16
    w = sum(i.width for i in images) + pad * (len(images) + 1)
    h = max(i.height for i in images) + pad * 2
    sheet = Image.new("RGBA", (w, h), (0x8A, 0x80, 0x88, 255))
    x = pad
    for i in images:
        sheet.alpha_composite(i, (x, h - pad - i.height))
        x += i.width + pad
    path = os.path.join(ROOT, "build", "refs_contact.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    sheet.save(path)
    print(f"  contact sheet -> {os.path.relpath(path, ROOT)}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", action="store_true")
    args = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    print("cut-outs:")
    made = [cut(*job) for job in JOBS]
    print("rooms:")
    rooms()
    if args.sheet:
        contact_sheet(made)


if __name__ == "__main__":
    sys.exit(main())
