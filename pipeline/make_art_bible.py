#!/usr/bin/env python3
"""
Build the art bible PDF from the reference images.

No PDF library is installed and none is needed. JPEGs can be dropped into a
PDF byte-for-byte using the DCTDecode filter - a PDF image XObject and a
baseline JPEG are the same compressed data - so this writes the PDF file
format directly and embeds the already-converted JPEGs without touching
their pixels.

    blender -b --python pipeline/convert_refs.py   # refs -> build/refjpg
    python3 pipeline/make_art_bible.py             # -> docs/ART_BIBLE.pdf
"""

import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JPG_DIR = os.path.join(ROOT, "build", "refjpg")
OUT = os.path.join(ROOT, "docs", "ART_BIBLE.pdf")

# A4 landscape, in PostScript points.
PW, PH = 842.0, 595.0
MARGIN = 38.0

# --------------------------------------------------------------------------
# Palette, measured from the reference images by pipeline/extract_palette.py
# --------------------------------------------------------------------------

SIGNAL_SWATCHES = [
    ("Nib Teal", "35D6C4", "Player shots, the pen-nib glow, power-ups"),
    ("Hostile Magenta", "FF2E6E", "Enemy bullets. Nothing else, ever."),
    ("Plume Ember", "F06A2A", "Hero plume, candle flame, explosive barrels"),
    ("Graze Gold", "FFC93C", "Graze meter, graze sparks, Shockwave ring"),
]

WORLD_SWATCHES = [
    ("Parchment", "E2C5A8", "Paper, cape, gilt filigree, UI text"),
    ("Candle Warm", "BE9E91", "Lit wall near a candle, warm floor pool"),
    ("Stone Lit", "8A8088", "Floor in light - the room's dominant value"),
    ("Stone Mid", "776B70", "Wall faces"),
    ("Stone Shadow", "554F59", "Wall shadow, floor away from light"),
    ("Ink Violet", "3C2C39", "Deep shadow, recesses"),
    ("Ink Black", "18030A", "Ink pools, outlines, the void"),
]

CREATURE_SWATCHES = [
    ("Creature Violet", "886181", "Enemy flesh, fur, slug bodies"),
    ("Creature Rust", "BA7977", "Enemy hide, shells, cloth"),
    ("Deep Plum", "421C39", "Enemy shadow side"),
    ("Steel", "868178", "Hero armour"),
]


# --------------------------------------------------------------------------
# Minimal PDF writer
# --------------------------------------------------------------------------

class PDF:
    def __init__(self):
        self.objects = [None]        # 1-indexed; objects[0] unused

    def add(self, body: bytes) -> int:
        self.objects.append(body)
        return len(self.objects) - 1

    def reserve(self) -> int:
        self.objects.append(None)
        return len(self.objects) - 1

    def set(self, num: int, body: bytes) -> None:
        self.objects[num] = body

    def write(self, path: str, root_num: int) -> None:
        out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
        offsets = [0] * len(self.objects)
        for i in range(1, len(self.objects)):
            offsets[i] = len(out)
            out += b"%d 0 obj\n" % i
            out += self.objects[i]
            out += b"\nendobj\n"

        xref_at = len(out)
        n = len(self.objects)
        out += b"xref\n0 %d\n" % n
        out += b"0000000000 65535 f \n"
        for i in range(1, n):
            out += b"%010d 00000 n \n" % offsets[i]
        out += b"trailer\n<< /Size %d /Root %d 0 R >>\n" % (n, root_num)
        out += b"startxref\n%d\n%%%%EOF\n" % xref_at

        with open(path, "wb") as fh:
            fh.write(bytes(out))


def jpeg_info(path):
    """(width, height, components) from a baseline JPEG's SOF marker."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:2] != b"\xff\xd8":
        raise ValueError(f"{path}: not a JPEG")
    i = 2
    while i < len(data) - 1:
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        # Standalone markers carry no length.
        if marker in (0xD8, 0xD9) or 0xD0 <= marker <= 0xD7:
            i += 2
            continue
        seg_len = struct.unpack(">H", data[i + 2:i + 4])[0]
        # SOF0..SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
        if 0xC0 <= marker <= 0xCF and marker not in (0xC4, 0xC8, 0xCC):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            comps = data[i + 9]
            return w, h, comps, data
        i += 2 + seg_len
    raise ValueError(f"{path}: no SOF marker found")


def esc(s: str) -> bytes:
    """Escape a string for a PDF literal, and drop anything non-Latin-1."""
    out = []
    for ch in s:
        if ch in "()\\":
            out.append("\\" + ch)
        elif ord(ch) < 256:
            out.append(ch)
        else:
            out.append("-")
    return "".join(out).encode("latin-1")


def rgb(hex_str):
    h = hex_str.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


# --------------------------------------------------------------------------
# Page content builders
# --------------------------------------------------------------------------

def text(x, y, size, s, font=b"/F1", colour=(1, 1, 1)):
    r, g, b = colour
    return (b"BT %s %.1f Tf %.3f %.3f %.3f rg 1 0 0 1 %.2f %.2f Tm (%s) Tj ET\n"
            % (font, size, r, g, b, x, y, esc(s)))


def rect(x, y, w, h, colour):
    r, g, b = colour
    return b"%.3f %.3f %.3f rg %.2f %.2f %.2f %.2f re f\n" % (
        r, g, b, x, y, w, h)


def wrap(s, width_chars):
    words, lines, cur = s.split(), [], ""
    for w in words:
        if len(cur) + len(w) + 1 <= width_chars:
            cur = (cur + " " + w).strip()
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


BG = rgb("1A1620")
FG = rgb("E2C5A8")
DIM = rgb("8A8088")
ACCENT = rgb("35D6C4")


def cover_page():
    c = rect(0, 0, PW, PH, BG)
    y = PH - 70
    c += text(MARGIN, y, 30, "PROJECT 5 - ART BIBLE", font=b"/F2", colour=FG)
    y -= 26
    c += text(MARGIN, y, 12,
              "Visual reference pack. Supersedes the Art direction section "
              "of GDD.pdf.", colour=DIM)
    y -= 34
    c += text(MARGIN, y, 15, "The concept, in one line", font=b"/F2",
              colour=ACCENT)
    y -= 20
    for line in wrap(
            "A knight armed with a giant pen nib fights his way out of an "
            "illuminated manuscript. The enemies are medieval marginalia come "
            "to life - the hare archer, the armoured snail, the grotesque "
            "hybrid - and the final boss is an ink-wraith scribe. The dungeon "
            "is a scriptorium: candles, quills, loose pages, and spreading "
            "pools of black ink.", 112):
        c += text(MARGIN, y, 11, line, colour=FG)
        y -= 15

    y -= 16
    c += text(MARGIN, y, 15, "Technique", font=b"/F2", colour=ACCENT)
    y -= 20
    for line in wrap(
            "Hand-inked illustration, not 3D and not pixel art. Bold black "
            "ink contour lines of varying weight, flat to lightly-washed "
            "colour inside them, visible paper grain. Muted, limited palette. "
            "Everything is drawn from a fixed 3/4 top-down view so it reads "
            "on a tilemap.", 112):
        c += text(MARGIN, y, 11, line, colour=FG)
        y -= 15

    # Palette blocks
    y -= 18
    c += text(MARGIN, y, 15, "Measured palette", font=b"/F2", colour=ACCENT)
    y -= 13
    c += text(MARGIN, y, 9,
              "Clustered from the reference images by "
              "pipeline/extract_palette.py - not picked by eye.", colour=DIM)
    y -= 22

    col_x = [MARGIN, MARGIN + 270, MARGIN + 540]
    groups = [("SIGNAL  (gameplay - never on scenery)", SIGNAL_SWATCHES),
              ("WORLD  (environment)", WORLD_SWATCHES),
              ("CREATURE + HERO", CREATURE_SWATCHES)]
    for ci, (title, swatches) in enumerate(groups):
        x = col_x[ci]
        yy = y
        c += text(x, yy, 10, title, font=b"/F2", colour=FG)
        yy -= 16
        for name, hexv, use in swatches:
            c += rect(x, yy - 9, 22, 14, rgb(hexv))
            c += text(x + 28, yy - 5, 9, f"{name}  #{hexv}", colour=FG)
            c += text(x + 28, yy - 15, 7.5, use[:46], colour=DIM)
            yy -= 27

    c += text(MARGIN, 26, 8,
              "Generated by pipeline/make_art_bible.py - "
              "re-run after changing the references.", colour=DIM)
    return c


def palette_rule_page():
    c = rect(0, 0, PW, PH, BG)
    y = PH - 64
    c += text(MARGIN, y, 24, "RULES", font=b"/F2", colour=FG)
    y -= 34

    rules = [
        ("Hostile Magenta is for enemy bullets and nothing else.",
         "This is the hardest rule in the project and it survives the art "
         "change unaltered. The core mechanic is grazing within 20 px of a "
         "bullet. If a bullet is ever ambiguous against scenery, the mechanic "
         "stops working. No scenery, no creature, no prop may be magenta or "
         "pink."),
        ("Teal belongs to the player.",
         "The nib glow, the player's shots and the damage power-up. The hero "
         "is the only warm-steel-and-teal thing on screen, so he never gets "
         "lost in a room full of violet creatures."),
        ("The environment stays desaturated and mid-value.",
         "Reference floors cluster around #8A8088 and #554F59 - grey-violet, "
         "low contrast, no busy texture where bullets travel. Ornament lives "
         "on the WALLS, where nothing is dodged. The floor earns its interest "
         "from light and ink pools, not from pattern."),
        ("Warm light, cool world.",
         "Candles and the light shaft push amber into a violet-grey room. "
         "That contrast is what makes the painted references feel lit rather "
         "than flat. Light direction is fixed: key from the top-left."),
        ("Ink is the theme and the threat.",
         "Black ink pools on the floor, drips off the boss, and splatters "
         "where things die. It doubles as the darkest value in the palette, "
         "so it always reads."),
        ("Silhouette first.",
         "Each enemy must be identifiable as a black shape: the snail is a "
         "circle on a wedge, the hare is tall ears over a thin body, the "
         "rat-demon is a hunched arc with a long tail. If two enemies share a "
         "silhouette, one of them is wrong."),
    ]
    for title, body in rules:
        c += text(MARGIN, y, 13, title, font=b"/F2", colour=ACCENT)
        y -= 17
        for line in wrap(body, 125):
            c += text(MARGIN + 10, y, 10, line, colour=FG)
            y -= 13
        y -= 12
    return c


CAPTIONS = {
    "props-sheet.jpg": (
        "PROPS - the three interactive objects, plus the power-up",
        "Maps one-to-one onto the GDD's Environmental Combat table. Explosive "
        "Lamp Oil is the explosive barrel: glass flask of burning oil in a "
        "rope net, lit wick, 2 hits to detonate, 30 damage within 96 px. "
        "Defensive Tome Stack is the destructible cover, and the sheet "
        "already gives the three damage stages the scaffold needs - strapped "
        "and locked, split with pages spilling, then shredded - across 5 "
        "hits. Scribe's Trap is the trap: a rusted frame of upturned PEN NIBS, "
        "shown disarmed, armed, and freshly triggered with violet ink on the "
        "points; 15 damage, re-arms after 2 s. Luminous Pigment Shell is the "
        "damage power-up that drops every 5th kill - teal, because teal is "
        "the player's colour, and a shell, which quietly ties it to the "
        "snail. Note the whole sheet is drawn at a 3/4 view matching the "
        "character rig."),
    "hero-nib-knight.jpg": (
        "HERO - the Nib Knight  (the anchor asset)",
        "The only hero reference. Stocky, large-helmed proportions: head and "
        "helm roughly a third of total height, short legs, broad stance. "
        "Steel plate (#868178) kept almost colourless, tattered parchment "
        "cape (#E2C5A8), and exactly two points of colour - the ember plume "
        "(#DD976D to #F06A2A) and the teal pen-nib (#98E5DD to #35D6C4). "
        "The nib is the weapon and the brightest thing on him; it is what "
        "the player's eye tracks. Every other asset is checked against this "
        "one for scale, line weight, light direction and palette."),
    "enemy-rat-demon.jpg": (
        "ENEMY - Grotesque  (elite tier)",
        "Hunched arc silhouette with a long curling tail. Rust hide over "
        "violet underside, the classic marginalia grotesque: a second "
        "grinning face set into the belly. Heavy ink contour, hatching "
        "inside the form rather than rendering. Reads as the big, slow, "
        "frightening one - use for the elite tier."),
    "enemy-armored-snail.jpg": (
        "ENEMY - Knight Snail  (standard tier, armoured)",
        "The knight-versus-snail joke is the single most common gag in real "
        "illuminated manuscript margins, which makes this the most on-theme "
        "enemy in the set. Circle-on-a-wedge silhouette. Rust shell fused to "
        "a steel great helm, violet slug foot, leather straps, a pennant and "
        "a couched lance. Slow mover, hard front, soft flank - the shape "
        "already tells the player how to fight it."),
    "enemy-hare-archer.jpg": (
        "ENEMY - Hare Archer  (standard tier, ranged)",
        "Tall-ears silhouette, unmistakable at a glance and unmistakably "
        "different from the snail. Violet fur, rust hood and cape. This is "
        "the ranged enemy the GDD asks to hold 150-250 px and take cover - "
        "the drawn bow telegraphs that role before it fires a shot."),
    "boss-ink-scribe.jpg": (
        "BOSS - the Ink Scribe  (room 8)",
        "Faceless hooded scribe dissolving into black ink, holding a quill. "
        "Robe in pale parchment going violet in shadow; the lower half is "
        "not a body at all but a spreading pool. The boss IS the ink that "
        "stains the dungeon floor, which ties the whole environment to him."),
    "room-boss-arena-pixel.jpg": (
        "GAMEPLAY REFERENCE - arena, readability, bullet colour",
        "Take the READABILITY from this, not the pixel technique. Note what "
        "it proves: magenta bullets and teal player shots are legible "
        "against grey-violet stone at speed; the floor's mandala inlay is "
        "low-contrast enough to dodge over; ink pools sit flat on the ground "
        "and never compete with projectiles; ornament is on pillars and "
        "edges, away from the fighting space. Bounded arena, whole room on "
        "screen at once."),
    "room-painted-interior.jpg": (
        "ENVIRONMENT - the master reference  (highest priority)",
        "This sets the look for everything. Room as a shallow diorama: floor "
        "as a quadrilateral with three walls visible, not a flat square of "
        "tiles. Ornate gilt vine filigree and arched doors on the walls; the "
        "floor left plain grey-violet so bullets read. Warm candle light "
        "with a visible shaft falling across cool stone. Scattered storytelling "
        "props - loose pages, quills, a candle, a dropped flower - and spilled "
        "ink pools. Four doors, one per wall, matching the GDD's room model."),
}

ORDER = [
    "room-painted-interior.jpg",
    "room-boss-arena-pixel.jpg",
    "hero-nib-knight.jpg",
    "props-sheet.jpg",
    "enemy-armored-snail.jpg",
    "enemy-hare-archer.jpg",
    "enemy-rat-demon.jpg",
    "boss-ink-scribe.jpg",
]


def room_brief_page():
    """
    The room framing, drawn rather than described.

    An artist needs to see where the floor goes, not read four coordinates
    and hope. Every room image that lands its floor in this rectangle shares
    one collision polygon, so a new layout costs a PNG and one line of JSON.
    """
    c = rect(0, 0, PW, PH, BG)
    y = PH - 56
    c += text(MARGIN, y, 24, "ROOM BRIEF", font=b"/F2", colour=FG)
    y -= 20
    c += text(MARGIN, y, 10,
              "Full spec in docs/ROOM_BRIEF.md. Hit this framing and a new "
              "room needs no engine work at all.", colour=DIM)

    # --- the framing diagram, drawn to scale ---------------------------
    scale = 0.46
    dw, dh = 1152 * scale, 640 * scale
    dx, dy = MARGIN, PH - 110 - dh

    def X(px):
        return dx + px * scale

    def Y(py):
        # Image Y grows down; PDF Y grows up.
        return dy + (640 - py) * scale

    # Wall bands, then the floor on top.
    c += rect(dx, dy, dw, dh, rgb("554F59"))
    c += rect(X(130), Y(613), (1022 - 130) * scale, (613 - 132) * scale,
              rgb("8A8088"))

    # Door anchors.
    for label, (px, py) in (("N", (440, 132)), ("N", (710, 132)),
                            ("W", (130, 373)), ("E", (1022, 373))):
        c += rect(X(px) - 7, Y(py) - 7, 14, 14, rgb("70280C"))
        c += text(X(px) - 3, Y(py) - 3, 8, label, font=b"/F2",
                  colour=rgb("E2C5A8"))

    c += text(X(430), Y(300), 11, "FLOOR - keep quiet", font=b"/F2",
              colour=rgb("3C2C39"))
    c += text(X(360), Y(60), 9, "ornament lives on the walls",
              colour=rgb("E2C5A8"))
    c += text(dx, dy - 14, 9,
              "1152 x 640 canvas   -   floor x 130..1022, y 132..613   -   "
              "side walls lean outward; no south wall",
              colour=DIM)

    # --- notes column ---------------------------------------------------
    cx = dx + dw + 24
    yy = PH - 112
    c += text(cx, yy, 13, "Rules", font=b"/F2", colour=ACCENT)
    yy -= 18
    for line in ("Fixed 3/4, 45 deg, ORTHOGRAPHIC.",
                 "Walls do not converge.",
                 "Three walls: top, left, right.",
                 "Ornament on walls. Floor stays plain",
                 "   - bullets fly there.",
                 "Warm candlelight from top-left",
                 "   across cool grey-violet stone.",
                 "Ink pools and loose pages, flat",
                 "   on the floor, never tall."):
        c += text(cx, yy, 9.5, line, colour=FG)
        yy -= 13

    yy -= 10
    c += text(cx, yy, 13, "Never on scenery", font=b"/F2",
              colour=rgb("FF2E6E"))
    yy -= 18
    c += rect(cx, yy - 3, 16, 11, rgb("FF2E6E"))
    c += text(cx + 22, yy, 9, "#FF2E6E - enemy bullets only", colour=FG)
    yy -= 16
    c += rect(cx, yy - 3, 16, 11, rgb("35D6C4"))
    c += text(cx + 22, yy, 9, "#35D6C4 - the player's colour", colour=FG)

    # --- prompt ----------------------------------------------------------
    yy = dy - 34
    c += text(MARGIN, yy, 12, "Append to every room prompt", font=b"/F2",
              colour=ACCENT)
    yy -= 15
    prompt = ("top-down 3/4 orthographic view of a gothic scriptorium "
              "chamber, hand-inked illustration with bold dark contour lines "
              "and flat painterly colour, ornate gilt vine filigree and "
              "arched timber doors on the stone walls, plain low-contrast "
              "grey-violet flagstone floor, spilled black ink pools and "
              "scattered manuscript pages, warm candlelight from the upper "
              "left across cool stone, limited palette of grey-violet stone, "
              "parchment cream, gold and ember orange, no magenta, no teal, "
              "no text, clean readable composition, empty centre")
    for line in wrap(prompt, 142):
        c += text(MARGIN, yy, 9, line, colour=FG)
        yy -= 11
    return c


def build():
    pdf = PDF()
    root = pdf.reserve()
    pages_obj = pdf.reserve()

    font_r = pdf.add(b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica "
                     b"/Encoding /WinAnsiEncoding >>")
    font_b = pdf.add(b"<< /Type /Font /Subtype /Type1 "
                     b"/BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>")

    page_nums = []

    def emit_page(content: bytes, image_ref=None):
        stream = zlib.compress(content)
        cont = pdf.add(b"<< /Length %d /Filter /FlateDecode >>\nstream\n"
                       % len(stream) + stream + b"\nendstream")
        xobj = b""
        if image_ref is not None:
            xobj = b" /XObject << /Im0 %d 0 R >>" % image_ref
        pg = pdf.add(
            b"<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %.0f %.0f] "
            b"/Resources << /Font << /F1 %d 0 R /F2 %d 0 R >>%s >> "
            b"/Contents %d 0 R >>"
            % (pages_obj, PW, PH, font_r, font_b, xobj, cont))
        page_nums.append(pg)

    emit_page(cover_page())
    emit_page(palette_rule_page())
    emit_page(room_brief_page())

    missing = []
    for name in ORDER:
        path = os.path.join(JPG_DIR, name)
        if not os.path.exists(path):
            missing.append(name)
            continue
        w, h, comps, data = jpeg_info(path)
        cs = b"/DeviceRGB" if comps == 3 else b"/DeviceGray"
        img = pdf.add(
            b"<< /Type /XObject /Subtype /Image /Width %d /Height %d "
            b"/ColorSpace %s /BitsPerComponent 8 /Filter /DCTDecode "
            b"/Length %d >>\nstream\n" % (w, h, cs, len(data))
            + data + b"\nendstream")

        title, body = CAPTIONS.get(name, (name, ""))
        lines = wrap(body, 128)
        caption_h = 15 + len(lines) * 12

        box_x = MARGIN
        box_y = MARGIN + caption_h + 10
        box_w = PW - MARGIN * 2
        box_h = PH - box_y - 56

        scale = min(box_w / w, box_h / h)
        dw, dh = w * scale, h * scale
        dx = box_x + (box_w - dw) * 0.5
        dy = box_y + (box_h - dh) * 0.5

        c = rect(0, 0, PW, PH, BG)
        c += text(MARGIN, PH - 44, 17, title, font=b"/F2", colour=ACCENT)
        # A thin parchment frame so cut-out art reads against the dark page.
        c += rect(dx - 3, dy - 3, dw + 6, dh + 6, rgb("3C2C39"))
        c += b"q %.3f 0 0 %.3f %.3f %.3f cm /Im0 Do Q\n" % (dw, dh, dx, dy)
        yy = MARGIN + caption_h - 12
        for line in lines:
            c += text(MARGIN, yy, 10, line, colour=FG)
            yy -= 12
        emit_page(c, image_ref=img)

    kids = b" ".join(b"%d 0 R" % n for n in page_nums)
    pdf.set(pages_obj,
            b"<< /Type /Pages /Count %d /Kids [%s] >>"
            % (len(page_nums), kids))
    pdf.set(root, b"<< /Type /Catalog /Pages %d 0 R >>" % pages_obj)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    pdf.write(OUT, root)

    size_mb = os.path.getsize(OUT) / 1024.0 / 1024.0
    print(f"[bible] {OUT}  ({len(page_nums)} pages, {size_mb:.1f} MB)")
    if missing:
        print("[bible] MISSING (run convert_refs.py first):", missing)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(build())
