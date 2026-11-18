"""
Normalise the reference images to baseline JPEG for the art-bible PDF.

Run through Blender, which decodes PNG and JPEG and can resize:

    blender -b --python pipeline/convert_refs.py

Output goes to a scratch folder, not the repo - the PDF carries the images,
so there is no reason to commit a second copy of each one.
"""

import os

import bpy

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REF_DIR = os.path.join(ROOT, "docs", "reference")
OUT_DIR = os.path.join(ROOT, "build", "refjpg")

# Long edge in pixels. Big enough to see brushwork at full-page size, small
# enough that the PDF stays a few MB rather than twenty.
MAX_EDGE = 1500


def convert(name):
    src = os.path.join(REF_DIR, name)
    img = bpy.data.images.load(src, check_existing=False)

    w, h = img.size
    scale = min(1.0, MAX_EDGE / float(max(w, h)))
    if scale < 1.0:
        img.scale(int(round(w * scale)), int(round(h * scale)))

    # Flatten any alpha onto white. PDF's DCTDecode has no alpha channel, and
    # the character sheets are cut out on transparency.
    if img.channels == 4:
        px = list(img.pixels[:])
        for i in range(0, len(px), 4):
            a = px[i + 3]
            if a < 1.0:
                for c in range(3):
                    px[i + c] = px[i + c] * a + (1.0 - a)
                px[i + 3] = 1.0
        img.pixels[:] = px

    base = os.path.splitext(name)[0] + ".jpg"
    dst = os.path.join(OUT_DIR, base)
    img.filepath_raw = dst
    img.file_format = "JPEG"
    # Baseline JPEG, high quality. Progressive JPEG is not reliably supported
    # by PDF readers via DCTDecode, and Blender writes baseline.
    bpy.context.scene.render.image_settings.quality = 88
    img.save()
    bpy.data.images.remove(img)
    print(f"[ref] {name} -> {base}  ({img.size[0] if False else ''})")
    return dst


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name in sorted(os.listdir(REF_DIR)):
        if name.lower().endswith((".png", ".jpg", ".jpeg")):
            convert(name)
    print("[ref] done ->", OUT_DIR)


if __name__ == "__main__":
    main()
