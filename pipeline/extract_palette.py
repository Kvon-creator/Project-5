"""
Pull the real palette out of the reference images.

The art direction changed from the GDD's description to a set of reference
illustrations. Rather than eyeball the new colours, this clusters the actual
pixels so the palette we build on is measured, not remembered.

Run through Blender, which can decode both PNG and JPEG and ships numpy:

    blender -b --python pipeline/extract_palette.py
"""

import os
import sys

import bpy
import numpy as np

REF_DIR = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "docs", "reference")

# Character sheets sit on a transparency checkerboard or on parchment. Those
# backgrounds are near-neutral and light, so they are filtered out before
# clustering; otherwise every character's palette comes back as "grey".
CHARACTER_IMAGES = [
    "enemy-rat-demon.jpg",
    "enemy-armored-snail.jpg",
    "enemy-hare-archer.jpg",
    "hero-nib-knight.png",
    "boss-ink-scribe.png",
]

# Environment references keep their neutrals - stone grey IS the subject.
ENVIRONMENT_IMAGES = [
    "room-painted-interior.png",
    "room-boss-arena-pixel.png",
]


def load_rgba(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    # Blender gives bottom-up; irrelevant for colour stats.
    return px


def srgb(x):
    """Blender hands back linear floats for PNG/JPEG; convert for display."""
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, x * 12.92,
                    1.055 * np.power(x, 1 / 2.4) - 0.055)


def kmeans(data, k, iters=24, seed=0):
    rng = np.random.default_rng(seed)
    # k-means++ style seeding: spread the initial centres out.
    centres = [data[rng.integers(len(data))]]
    for _ in range(k - 1):
        d = np.min(np.linalg.norm(data[:, None] - np.array(centres)[None], axis=2),
                   axis=1)
        probs = d ** 2
        total = probs.sum()
        if total <= 0:
            centres.append(data[rng.integers(len(data))])
            continue
        centres.append(data[rng.choice(len(data), p=probs / total)])
    centres = np.array(centres)

    for _ in range(iters):
        dist = np.linalg.norm(data[:, None] - centres[None], axis=2)
        labels = np.argmin(dist, axis=1)
        for i in range(k):
            sel = data[labels == i]
            if len(sel):
                centres[i] = sel.mean(axis=0)
    dist = np.linalg.norm(data[:, None] - centres[None], axis=2)
    labels = np.argmin(dist, axis=1)
    weights = np.array([(labels == i).sum() for i in range(k)], dtype=np.float32)
    return centres, weights / weights.sum()


def analyse(filename, keep_neutrals, k=8, sample=24000):
    path = os.path.join(REF_DIR, filename)
    if not os.path.exists(path):
        print(f"  !! missing {filename}")
        return
    px = load_rgba(path)
    flat = px.reshape(-1, 4)

    # Drop transparent pixels.
    flat = flat[flat[:, 3] > 0.6][:, :3]
    disp = srgb(flat)

    if not keep_neutrals:
        mx = disp.max(axis=1)
        mn = disp.min(axis=1)
        sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
        # Light and desaturated = checkerboard or parchment, not the subject.
        keep = ~((sat < 0.18) & (mx > 0.62))
        disp = disp[keep]

    if len(disp) == 0:
        print(f"  !! {filename}: nothing left after filtering")
        return

    rng = np.random.default_rng(1)
    if len(disp) > sample:
        disp = disp[rng.choice(len(disp), sample, replace=False)]

    centres, weights = kmeans(disp, k)
    order = np.argsort(-weights)

    print(f"\n{filename}  ({len(disp)} px sampled)")
    for i in order:
        r, g, b = (np.clip(centres[i], 0, 1) * 255).round().astype(int)
        print(f"   #{r:02X}{g:02X}{b:02X}   {weights[i] * 100:5.1f}%")


def main():
    print("=" * 56)
    print("CHARACTERS  (background filtered out)")
    print("=" * 56)
    for name in CHARACTER_IMAGES:
        analyse(name, keep_neutrals=False)

    print("\n" + "=" * 56)
    print("ENVIRONMENT  (neutrals kept - stone is the subject)")
    print("=" * 56)
    for name in ENVIRONMENT_IMAGES:
        analyse(name, keep_neutrals=True, k=10)


if __name__ == "__main__":
    main()
