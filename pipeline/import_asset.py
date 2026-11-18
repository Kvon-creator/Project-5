"""
Import generated 2D art as a correctly sized game sprite.

Image models output art at whatever size they like - typically 1024 px plus
on a transparent background. The game needs each prop at an exact scale
relative to the 64 px hero, centred in the exact frame the scenes already
reference. Doing that by eye in an editor is the kind of step that silently
drifts; this makes it one command:

    blender -b --python pipeline/import_asset.py -- \\
        --src ~/Downloads/generated_barrel.png \\
        --out assets/sprites/props/barrel.png \\
        --frame 80 --content-height 40

What it does:
  1. finds the art's bounding box from its alpha channel
  2. scales it so the content height hits --content-height pixels
  3. centres it in a transparent --frame x --frame canvas
  4. saves straight over the sprite path the scenes point at

Horizontal centring, and the content sits with equal margin above and below
the frame centre - matching how the Blender-rendered props were framed, so
the collision shapes and sprite offsets in the scenes keep working.

Requires a transparent background: the crop keys on alpha. If your generator
cannot export transparency, remove the background first.
"""

import argparse
import os
import sys

import bpy
import numpy as np

ALPHA_FLOOR = 0.06   # ignore faint halo pixels left by background removal


def parse_args():
    # Blender passes everything after "--" through to the script.
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True, help="generated image (with alpha)")
    ap.add_argument("--out", required=True, help="sprite path to write")
    ap.add_argument("--frame", type=int, required=True,
                    help="output canvas size in px (square)")
    ap.add_argument("--content-height", type=int, required=True,
                    help="how tall the art should be in the frame, in px")
    return ap.parse_args(argv)


def load_pixels(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return px  # bottom-up row order, Blender convention


def alpha_bbox(px):
    mask = px[:, :, 3] > ALPHA_FLOOR
    if not mask.any():
        raise SystemExit("ERROR: image has no opaque pixels. The import "
                         "keys on transparency - remove the background "
                         "before importing.")
    rows = np.where(mask.any(axis=1))[0]
    cols = np.where(mask.any(axis=0))[0]
    return rows.min(), rows.max(), cols.min(), cols.max()


def scale_image(px, new_w, new_h):
    """Scale through Blender's own resampler rather than hand-rolling one."""
    h, w = px.shape[0], px.shape[1]
    # Byte buffer, not float: float images default to a linear colourspace
    # and save as 16-bit PNGs, which both shifts the colours through an
    # unwanted conversion and produces files check_anchor cannot read.
    img = bpy.data.images.new("tmp_scale", width=w, height=h, alpha=True)
    img.pixels[:] = px.ravel()
    img.scale(new_w, new_h)
    out = np.array(img.pixels[:], dtype=np.float32).reshape(new_h, new_w, 4)
    bpy.data.images.remove(img)
    return out


def main():
    args = parse_args()
    src = os.path.expanduser(args.src)
    if not os.path.exists(src):
        raise SystemExit(f"ERROR: {src} not found")

    px = load_pixels(src)
    r0, r1, c0, c1 = alpha_bbox(px)
    content = px[r0:r1 + 1, c0:c1 + 1, :]
    ch, cw = content.shape[0], content.shape[1]

    scale = args.content_height / float(ch)
    new_h = args.content_height
    new_w = max(1, int(round(cw * scale)))
    if new_w > args.frame:
        # Wider than tall relative to the frame: fit by width instead and
        # say so, because the caller's content-height was not achievable.
        fit = args.frame / float(new_w)
        new_w = args.frame
        new_h = max(1, int(round(args.content_height * fit)))
        print(f"[import] NOTE: art is wide; fitting by width, content "
              f"height becomes {new_h}px (asked {args.content_height})")
    content = scale_image(content, new_w, new_h)

    frame = args.frame
    canvas = np.zeros((frame, frame, 4), dtype=np.float32)
    x0 = (frame - new_w) // 2
    y0 = (frame - new_h) // 2
    canvas[y0:y0 + new_h, x0:x0 + new_w, :] = content

    out_img = bpy.data.images.new("tmp_out", width=frame, height=frame,
                                  alpha=True)
    out_img.pixels[:] = canvas.ravel()
    out_path = os.path.abspath(os.path.expanduser(args.out))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out_img.filepath_raw = out_path
    out_img.file_format = "PNG"
    out_img.save()

    print(f"[import] {os.path.basename(src)}  {cw}x{ch}  ->  "
          f"{out_path}  (frame {frame}, content {new_w}x{new_h})")
    print("[import] verify:  python3 pipeline/check_anchor.py " + args.out)


if __name__ == "__main__":
    main()
