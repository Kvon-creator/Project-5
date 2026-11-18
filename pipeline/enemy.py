"""
The bestiary: Knight Snail, Hare Archer, Grotesque, and the Ink Scribe.

References:
    docs/reference/enemy-armored-snail.jpg
    docs/reference/enemy-hare-archer.jpg
    docs/reference/enemy-rat-demon.jpg
    docs/reference/boss-ink-scribe.png

These are marginalia - the creatures drawn in the margins of illuminated
manuscripts. The knight-versus-snail duel is the single most common gag in
real medieval margins, which is why the snail is armoured and carrying a
lance, and the hare archer is nearly as common. They are jokes from the book
the player is fighting their way out of.

Mapping onto the GDD's tiers, which drives HP and kill energy:

    Knight Snail   standard  40 HP    melee, slow, hard front
    Hare Archer    standard  40 HP    ranged - holds 150-250 px, takes cover
    Grotesque      elite     120 HP   the big one, from room 4
    Ink Scribe     boss      1200 HP  room 8

SILHOUETTE IS THE BRIEF. Each one has to be identifiable as a black shape:
the snail is a circle on a wedge, the hare is tall ears over a thin body,
the grotesque is a hunched arc with a long tail, the scribe is a cowled
column melting into a puddle. Colour is secondary - in a room full of
bullets the player reads shapes.

Run:
    blender -b --python pipeline/enemy.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

# Pixels per metre, inherited from the anchor asset: the Nib Knight is
# 1.60 m rendered into a 3.80 m frame at 128 px.
PX_PER_M = 128 / 3.80

# name:        (frame px, notes)
SPECIES = {
    # The snail needs a bigger frame than its body suggests: the pennant and
    # the couched lance both reach well past the shell, and at 128 px the
    # pennant was clipped off the top edge.
    "snail": 160,
    "hare": 128,
    "grotesque": 160,
    "scribe": 256,
}


def frame_m(frame_px):
    """Metres the frame covers, holding the anchor's pixels-per-metre."""
    return frame_px / PX_PER_M


def creature_materials(tag):
    """
    The shared creature palette.

    Every enemy is violet flesh plus rust hide. That is what the three
    references have in common, and keeping it strict is what makes a mixed
    wave read as one family - and as NOT the hero, who is steel and teal.
    """
    return {
        "violet": rig.cel_material(f"{tag}Violet", "886181",
                                   shadow_mix=0.30, highlight_mix=0.26),
        "rust": rig.cel_material(f"{tag}Rust", "BA7977",
                                 shadow_mix=0.30, highlight_mix=0.22),
        "plum": rig.cel_material(f"{tag}Plum", "421C39",
                                 shadow_mix=0.12, highlight_mix=0.30),
        "steel": rig.cel_material(f"{tag}Steel", "868178",
                                  shadow_mix=0.26, highlight_mix=0.32),
        "wood": rig.cel_material(f"{tag}Wood", "70280C",
                                 shadow_mix=0.26, highlight_mix=0.30),
        "parchment": rig.cel_material(f"{tag}Parch", "E2C5A8",
                                      shadow_mix=0.30, highlight_mix=0.16),
        "ink": rig.cel_material(f"{tag}Ink", "18030A",
                                shadow_mix=0.0, highlight_mix=0.14),
        "ember": rig.cel_material(f"{tag}Ember", "F06A2A",
                                  shadow_mix=0.30, highlight_mix=0.26),
    }


def disc_ring(name, location, radius, thickness, depth, material, verts=24):
    """A ring standing upright in the XZ plane - a shell whorl seen side-on."""
    ob = rig.add_ring(name, location, radius=radius, thickness=thickness,
                      height=depth, material=material, verts=verts)
    ob.rotation_euler = (math.radians(90.0), 0.0, 0.0)
    return ob


# --------------------------------------------------------------------------
# Knight Snail - standard, melee
# --------------------------------------------------------------------------

def build_snail():
    """
    Circle on a wedge. The shell is the whole read; everything else hangs
    off it. Low and long, so it never looks like it moves fast.
    """
    m = creature_materials("Snail")
    parts = []

    # ---- slug foot -------------------------------------------------------
    # A long, low wedge in violet. Flattened sphere rather than a box, so
    # the silhouette's underside is soft against the shell's hard circle.
    foot = rig.add_sphere("Foot", (0.0, 0.0, 0.20), radius=0.52,
                          material=m["violet"], segments=12, rings=7)
    foot.scale = (0.80, 1.75, 0.34)
    parts.append(foot)
    # The front of the foot, reaching forward (-Y) under the head.
    head_foot = rig.add_sphere("FootFront", (0.0, -0.95, 0.16), radius=0.34,
                               material=m["violet"], segments=10, rings=6)
    head_foot.scale = (0.72, 1.25, 0.30)
    parts.append(head_foot)

    # ---- eye stalks ------------------------------------------------------
    for side, x in (("L", -0.16), ("R", 0.16)):
        parts.append(rig.add_cylinder(
            f"Stalk{side}", (x, -1.22, 0.45), radius=0.035, depth=0.42,
            material=m["violet"], verts=6,
            rotation=(math.radians(-24.0), 0.0, 0.0)))
        parts.append(rig.add_sphere(f"Eye{side}", (x, -1.30, 0.66), 0.058,
                                    m["plum"], segments=8, rings=5))

    # ---- shell -----------------------------------------------------------
    # Concentric whorls of decreasing radius, each nudged forward and up, so
    # the spiral reads from the side the way a real shell does.
    whorls = [(0.78, 0.26, 0.00, 0.78), (0.56, 0.22, 0.06, 0.86),
              (0.37, 0.18, 0.11, 0.92), (0.21, 0.14, 0.15, 0.96)]
    for i, (r, t, dy, dz) in enumerate(whorls):
        parts.append(disc_ring(f"Whorl{i}", (0.0, 0.22 + dy, dz),
                               radius=r, thickness=t, depth=0.62,
                               material=m["rust"], verts=20))
    # Shell core, filling the middle of the spiral.
    core = rig.add_sphere("ShellCore", (0.0, 0.33, 0.92), radius=0.26,
                          material=m["rust"], segments=10, rings=6)
    core.scale = (0.62, 1.0, 1.0)
    parts.append(core)

    # ---- the great helm, fused to the front of the shell -----------------
    # This is the joke made literal: the snail wears a knight's helm.
    parts.append(rig.add_cylinder("Helm", (0.0, -0.46, 0.84),
                                  radius=0.40, depth=0.54, material=m["steel"],
                                  verts=10,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    parts.append(rig.add_cone("HelmBrow", (0.0, -0.74, 0.84),
                              radius1=0.40, radius2=0.33, depth=0.16,
                              material=m["steel"], verts=10,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))
    # Visor slit - the one dark horizontal band that gives it a face.
    parts.append(rig.add_box("Visor", (0.0, -0.80, 0.90),
                             (0.52, 0.08, 0.09), m["ink"]))
    # Cross-rib down the helm front, like the reference.
    parts.append(rig.add_box("HelmRib", (0.0, -0.80, 0.74),
                             (0.08, 0.08, 0.40), m["steel"]))

    # ---- straps ----------------------------------------------------------
    for i, dz in enumerate((0.55, 0.95)):
        parts.append(rig.add_box(f"Strap{i}", (0.0, 0.18, dz),
                                 (0.62, 0.14, 0.09), m["wood"]))

    # ---- pennant ---------------------------------------------------------
    parts.append(rig.add_cylinder("Pole", (0.22, 0.52, 1.38), radius=0.028,
                                  depth=0.78, material=m["wood"], verts=6))
    for i, (dz, w) in enumerate(((1.64, 0.40), (1.53, 0.32))):
        parts.append(rig.add_box(f"Flag{i}", (0.22 + w * 0.5, 0.52, dz),
                                 (w, 0.03, 0.22), m["ember"]))

    # ---- couched lance ---------------------------------------------------
    # Runs the length of the body and well past the head, which is what
    # tells the player this thing has a dangerous FRONT and a soft flank.
    parts.append(rig.add_cylinder("Lance", (-0.34, -0.30, 0.62),
                                  radius=0.045, depth=2.5, material=m["wood"],
                                  verts=6,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    parts.append(rig.add_cone("LanceTip", (-0.34, -1.68, 0.62),
                              radius1=0.09, radius2=0.0, depth=0.34,
                              material=m["steel"], verts=8,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))
    parts.append(rig.add_cone("LanceGuard", (-0.34, -1.42, 0.62),
                              radius1=0.14, radius2=0.07, depth=0.16,
                              material=m["steel"], verts=8,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))
    return parts


# --------------------------------------------------------------------------
# Hare Archer - standard, ranged
# --------------------------------------------------------------------------

def build_hare():
    """
    Tall ears over a thin upright body. The drawn bow telegraphs the role
    before the enemy fires: this is the one that keeps its distance.
    """
    m = creature_materials("Hare")
    parts = []

    # ---- legs ------------------------------------------------------------
    # Digitigrade: a long thigh, a long shin angled back, a big foot. That
    # backward-kinked leg is half of why a hare reads as a hare.
    for side, x in (("L", -0.17), ("R", 0.17)):
        parts.append(rig.add_box(f"Thigh{side}", (x, 0.10, 0.44),
                                 (0.21, 0.26, 0.46), m["violet"],
                                 rotation=(math.radians(-14.0), 0, 0)))
        parts.append(rig.add_box(f"Shin{side}", (x, -0.02, 0.17),
                                 (0.14, 0.15, 0.36), m["violet"],
                                 rotation=(math.radians(16.0), 0, 0)))
        parts.append(rig.add_box(f"Foot{side}", (x, -0.16, 0.04),
                                 (0.16, 0.42, 0.09), m["violet"]))

    # ---- torso -----------------------------------------------------------
    torso = rig.add_sphere("Torso", (0.0, 0.0, 0.90), radius=0.30,
                           material=m["violet"], segments=12, rings=7)
    torso.scale = (0.92, 0.78, 1.25)
    parts.append(torso)

    # ---- rust hood and cape ---------------------------------------------
    parts.append(rig.add_cone("Cape", (0.0, 0.10, 1.08),
                              radius1=0.40, radius2=0.26, depth=0.40,
                              material=m["rust"], verts=10))
    for i, (loc, size, tilt) in enumerate((
            ((0.0, 0.26, 0.86), (0.46, 0.07, 0.42), 12.0),
            ((-0.14, 0.28, 0.70), (0.20, 0.06, 0.30), 18.0))):
        parts.append(rig.add_box(f"CapeTail{i}", loc, size, m["rust"],
                                 rotation=(math.radians(tilt), 0, 0)))

    # ---- head ------------------------------------------------------------
    head = rig.add_sphere("Head", (0.0, -0.10, 1.33), radius=0.20,
                          material=m["violet"], segments=10, rings=6)
    head.scale = (0.90, 1.30, 0.92)
    parts.append(head)
    parts.append(rig.add_cone("Muzzle", (0.0, -0.33, 1.28),
                              radius1=0.12, radius2=0.06, depth=0.18,
                              material=m["violet"], verts=8,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))
    parts.append(rig.add_sphere("EyeL", (-0.13, -0.22, 1.38), 0.045,
                                m["parchment"], segments=7, rings=5))

    # Rust hood pushed back off the face, ears through it.
    hood = rig.add_sphere("Hood", (0.0, 0.05, 1.38), radius=0.23,
                          material=m["rust"], segments=10, rings=6)
    hood.scale = (1.0, 0.95, 0.85)
    parts.append(hood)

    # ---- ears - the silhouette ------------------------------------------
    # Long, upright, slightly splayed. At 48 px this is the ONLY thing that
    # needs to survive for the player to know what they are shooting at.
    for side, (x, yaw) in (("L", (-0.10, 9.0)), ("R", (0.10, -9.0))):
        parts.append(rig.add_cone(
            f"Ear{side}", (x, 0.02, 1.86), radius1=0.085, radius2=0.035,
            depth=0.74, material=m["violet"], verts=6,
            rotation=(math.radians(-7.0), 0.0, math.radians(yaw))))
        parts.append(rig.add_cone(
            f"EarIn{side}", (x, -0.045, 1.84), radius1=0.045, radius2=0.018,
            depth=0.62, material=m["plum"], verts=6,
            rotation=(math.radians(-7.0), 0.0, math.radians(yaw))))

    # ---- quiver ----------------------------------------------------------
    parts.append(rig.add_cylinder("Quiver", (-0.24, 0.26, 0.92), radius=0.11,
                                  depth=0.52, material=m["wood"], verts=8,
                                  rotation=(math.radians(16.0), 0.0,
                                            math.radians(-14.0))))
    for i in range(3):
        parts.append(rig.add_cylinder(
            f"Arrow{i}", (-0.26 + i * 0.045, 0.30, 1.24), radius=0.014,
            depth=0.30, material=m["parchment"], verts=5,
            rotation=(math.radians(16.0), 0.0, math.radians(-14.0))))

    # ---- arms and bow ----------------------------------------------------
    # Bow arm forward, string arm drawn back to the cheek.
    parts.append(rig.add_box("ArmBow", (0.30, -0.26, 1.08),
                             (0.11, 0.36, 0.11), m["violet"],
                             rotation=(0.0, math.radians(-16.0), 0.0)))
    parts.append(rig.add_box("ArmDraw", (-0.24, -0.04, 1.12),
                             (0.11, 0.26, 0.11), m["violet"]))

    # The bow: an open arc of overlapping beads. A torus here renders as a
    # closed wheel, which is what the first pass looked like.
    rig.add_arc(parts, "Bow", (0.40, -0.30, 1.08), radius=0.48,
                start_deg=-104.0, end_deg=104.0, bead_radius=0.042,
                material=m["wood"], segments=20, plane="yz", squash=0.55)
    # Recurved tips.
    for side, z in (("T", 1.08 + 0.48), ("B", 1.08 - 0.48)):
        parts.append(rig.add_sphere(f"Tip{side}", (0.40, -0.18, z), 0.04,
                                    m["wood"], segments=7, rings=5))

    # Bowstring, drawn back into a V.
    for i, tilt in enumerate((22.0, -22.0)):
        parts.append(rig.add_box(f"String{i}", (0.16, -0.44, 1.08),
                                 (0.012, 0.012, 0.52), m["parchment"],
                                 rotation=(math.radians(tilt), 0.0, 0.0)))
    # Nocked arrow, pointing forward.
    parts.append(rig.add_cylinder("Nocked", (0.26, -0.62, 1.08), radius=0.015,
                                  depth=0.62, material=m["parchment"],
                                  verts=5,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    parts.append(rig.add_cone("NockTip", (0.26, -0.96, 1.08),
                              radius1=0.035, radius2=0.0, depth=0.12,
                              material=m["steel"], verts=6,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))
    return parts


# --------------------------------------------------------------------------
# Grotesque - elite
# --------------------------------------------------------------------------

def build_grotesque():
    """
    A hunched arc with a long curling tail and a second face in its belly.

    The belly face is the detail that makes this a marginalia grotesque
    rather than a generic monster, and it survives at elite size, so it
    stays in.
    """
    m = creature_materials("Grot")
    parts = []

    # ---- hind legs -------------------------------------------------------
    for side, x in (("L", -0.34), ("R", 0.34)):
        parts.append(rig.add_box(f"Haunch{side}", (x, 0.52, 0.62),
                                 (0.34, 0.42, 0.56), m["violet"]))
        parts.append(rig.add_box(f"HindShin{side}", (x, 0.40, 0.22),
                                 (0.19, 0.20, 0.44), m["violet"],
                                 rotation=(math.radians(12.0), 0, 0)))
        parts.append(rig.add_box(f"HindFoot{side}", (x, 0.24, 0.05),
                                 (0.22, 0.42, 0.10), m["plum"]))

    # ---- body: an arching back ------------------------------------------
    # Built as three overlapping ellipsoids rising from hips to shoulders,
    # which gives the hunched arc the reference leads with.
    for i, (y, z, r, sx, sy, sz) in enumerate((
            (0.46, 0.96, 0.46, 1.0, 1.05, 0.80),
            (0.02, 1.08, 0.50, 1.05, 1.10, 0.78),
            (-0.44, 1.02, 0.46, 1.0, 1.05, 0.76))):
        seg = rig.add_sphere(f"Back{i}", (0.0, y, z), radius=r,
                             material=m["rust"], segments=12, rings=7)
        seg.scale = (sx, sy, sz)
        parts.append(seg)

    # Violet underside - the reference splits rust hide over violet belly.
    belly = rig.add_sphere("Belly", (0.0, 0.0, 0.72), radius=0.44,
                           material=m["violet"], segments=12, rings=7)
    belly.scale = (0.92, 1.45, 0.62)
    parts.append(belly)

    # ---- the belly face --------------------------------------------------
    face = rig.add_sphere("BellyFace", (0.0, -0.34, 0.62), radius=0.26,
                          material=m["violet"], segments=10, rings=6)
    face.scale = (1.0, 0.65, 1.0)
    parts.append(face)
    # A wide grin of small teeth.
    parts.append(rig.add_box("Grin", (0.0, -0.52, 0.54),
                             (0.34, 0.07, 0.10), m["ink"]))
    for i in range(5):
        parts.append(rig.add_box(f"GrinTooth{i}", (-0.13 + i * 0.065,
                                                   -0.55, 0.555),
                                 (0.035, 0.03, 0.07), m["parchment"]))
    for side, x in (("L", -0.10), ("R", 0.10)):
        parts.append(rig.add_box(f"GrinEye{side}", (x, -0.53, 0.72),
                                 (0.08, 0.04, 0.035), m["ink"]))

    # ---- fore legs -------------------------------------------------------
    for side, x in (("L", -0.30), ("R", 0.30)):
        parts.append(rig.add_box(f"Fore{side}", (x, -0.50, 0.50),
                                 (0.17, 0.19, 0.74), m["violet"]))
        parts.append(rig.add_box(f"Paw{side}", (x, -0.60, 0.07),
                                 (0.20, 0.34, 0.12), m["plum"]))
        for c in range(3):
            parts.append(rig.add_cone(
                f"Claw{side}{c}", (x - 0.06 + c * 0.06, -0.80, 0.055),
                radius1=0.025, radius2=0.0, depth=0.14, material=m["parchment"],
                verts=5, rotation=(math.radians(-90.0), 0.0, 0.0)))

    # ---- head ------------------------------------------------------------
    skull = rig.add_sphere("Skull", (0.0, -0.80, 1.28), radius=0.33,
                           material=m["rust"], segments=12, rings=7)
    skull.scale = (0.92, 1.08, 0.92)
    parts.append(skull)
    # Open jaws: upper and lower cones, hinged apart.
    parts.append(rig.add_cone("Upper", (0.0, -1.22, 1.30),
                              radius1=0.27, radius2=0.14, depth=0.52,
                              material=m["rust"], verts=8,
                              rotation=(math.radians(-78.0), 0.0, 0.0)))
    parts.append(rig.add_cone("Lower", (0.0, -1.16, 1.02),
                              radius1=0.23, radius2=0.11, depth=0.44,
                              material=m["violet"], verts=8,
                              rotation=(math.radians(-104.0), 0.0, 0.0)))
    parts.append(rig.add_box("Maw", (0.0, -1.22, 1.17),
                             (0.30, 0.22, 0.14), m["ink"]))
    for i in range(4):
        parts.append(rig.add_cone(f"FangU{i}", (-0.11 + i * 0.073, -1.33,
                                                1.18),
                                  radius1=0.032, radius2=0.0, depth=0.13,
                                  material=m["parchment"], verts=5,
                                  rotation=(math.radians(180.0), 0.0, 0.0)))
        parts.append(rig.add_cone(f"FangL{i}", (-0.11 + i * 0.073, -1.30,
                                                1.09),
                                  radius1=0.028, radius2=0.0, depth=0.11,
                                  material=m["parchment"], verts=5))
    # Pointed ears, swept back.
    for side, (x, yaw) in (("L", (-0.22, 22.0)), ("R", (0.22, -22.0))):
        parts.append(rig.add_cone(
            f"Ear{side}", (x, -0.62, 1.58), radius1=0.13, radius2=0.0,
            depth=0.38, material=m["rust"], verts=6,
            rotation=(math.radians(22.0), 0.0, math.radians(yaw))))
    parts.append(rig.add_sphere("EyeGlow", (0.14, -1.00, 1.38), 0.055,
                                m["parchment"], segments=7, rings=5))

    # ---- tail ------------------------------------------------------------
    # Curls up and back over the haunches. Beads overlap and taper; the
    # first pass spaced them wider than their radius and the tail rendered
    # as a line of floating bubbles trailing off into space.
    rig.add_arc(parts, "Tail", (0.0, 0.62, 1.00), radius=0.78,
                start_deg=-62.0, end_deg=96.0, bead_radius=0.17,
                material=m["violet"], segments=12, plane="yz",
                squash=-0.95, taper=0.30)

    return parts


# --------------------------------------------------------------------------
# Ink Scribe - boss
# --------------------------------------------------------------------------

def build_scribe():
    """
    A cowled column melting into a puddle.

    The reference has no legs and no face: the robe simply becomes ink
    somewhere below the waist. That ink is the same stuff pooled on every
    room's floor, which is the detail tying the whole dungeon to this fight.
    """
    m = creature_materials("Scribe")
    parts = []

    # ---- the spreading pool ---------------------------------------------
    # Rendered as overlapping flat discs. The boss stands IN his own spill.
    for i, (x, y, r) in enumerate(((0.0, 0.0, 1.08), (-0.78, 0.32, 0.62),
                                   (0.86, -0.22, 0.58), (0.18, 0.70, 0.52),
                                   (-0.40, -0.64, 0.48))):
        blob = rig.add_cylinder(f"Pool{i}", (x, y, 0.03), radius=r,
                                depth=0.06, material=m["ink"], verts=14)
        blob.scale = (1.0, 0.74, 1.0)
        parts.append(blob)

    # ---- robe ------------------------------------------------------------
    # Wide at the hem, narrowing to the shoulders. The bottom third is ink,
    # the top is parchment - the transition is the character.
    parts.append(rig.add_cone("RobeLow", (0.0, 0.0, 0.52),
                              radius1=0.92, radius2=0.74, depth=1.45,
                              material=m["ink"], verts=14))
    parts.append(rig.add_cone("RobeMid", (0.0, 0.0, 1.45),
                              radius1=0.74, radius2=0.56, depth=1.40,
                              material=m["plum"], verts=14))
    parts.append(rig.add_cone("RobeTop", (0.0, 0.0, 2.25),
                              radius1=0.66, radius2=0.48, depth=1.00,
                              material=m["parchment"], verts=14))

    # Drips hanging off the hem, varying length so it reads as running ink.
    for i, (ang, length) in enumerate(((20, 0.55), (75, 0.34), (130, 0.62),
                                       (200, 0.40), (255, 0.58),
                                       (310, 0.30))):
        a = math.radians(ang)
        parts.append(rig.add_cylinder(
            f"Drip{i}", (math.cos(a) * 0.86, math.sin(a) * 0.86,
                         0.12 + length * 0.5),
            radius=0.085, depth=length, material=m["ink"], verts=6))

    # ---- shoulders and cowl ---------------------------------------------
    parts.append(rig.add_cone("Mantle", (0.0, 0.0, 2.72),
                              radius1=0.62, radius2=0.40, depth=0.42,
                              material=m["parchment"], verts=12))
    cowl = rig.add_sphere("Cowl", (0.0, 0.10, 3.02), radius=0.44,
                          material=m["parchment"], segments=12, rings=7)
    cowl.scale = (1.0, 1.05, 1.1)
    parts.append(cowl)
    # Hood peak, swept back - the facing cue, same trick as the hero's plume.
    parts.append(rig.add_cone("Peak", (0.0, 0.42, 3.22),
                              radius1=0.34, radius2=0.05, depth=0.70,
                              material=m["parchment"], verts=8,
                              rotation=(math.radians(52.0), 0.0, 0.0)))
    # The void where a face should be. Faceless is the point.
    # Pushed clear of the cowl so the hole actually reads. Faceless is the
    # whole character; a void buried inside the hood sphere shows nothing.
    parts.append(rig.add_cylinder("Void", (0.0, -0.46, 2.96), radius=0.33,
                                  depth=0.22, material=m["ink"], verts=12,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))

    # ---- arms, quill, tome ----------------------------------------------
    # Right arm raised with the quill - the casting pose from the arena
    # reference. Left arm holds the book.
    parts.append(rig.add_cylinder("ArmR", (0.62, -0.30, 2.58), radius=0.14,
                                  depth=0.95, material=m["plum"], verts=8,
                                  rotation=(math.radians(28.0), 0.0,
                                            math.radians(-30.0))))
    parts.append(rig.add_sphere("HandR", (0.92, -0.48, 3.00), 0.14,
                                m["parchment"], segments=8, rings=5))
    # The quill: a long tapered feather, parchment, held point-down.
    parts.append(rig.add_cone("Quill", (1.02, -0.52, 3.46),
                              radius1=0.055, radius2=0.015, depth=1.05,
                              material=m["parchment"], verts=6,
                              rotation=(math.radians(16.0), 0.0,
                                        math.radians(-12.0))))
    for i, (dz, w) in enumerate(((3.70, 0.17), (3.52, 0.20), (3.34, 0.17))):
        parts.append(rig.add_box(f"Vane{i}", (1.06, -0.52, dz),
                                 (w, 0.03, 0.22), m["parchment"],
                                 rotation=(0.0, math.radians(14.0), 0.0)))
    # Ink loaded on the nib end.
    parts.append(rig.add_cone("QuillInk", (0.98, -0.52, 2.96),
                              radius1=0.05, radius2=0.0, depth=0.22,
                              material=m["ink"], verts=6,
                              rotation=(math.radians(180.0), 0.0, 0.0)))

    parts.append(rig.add_cylinder("ArmL", (-0.60, -0.26, 2.42), radius=0.14,
                                  depth=0.80, material=m["plum"], verts=8,
                                  rotation=(math.radians(-14.0), 0.0,
                                            math.radians(22.0))))
    parts.append(rig.add_box("Tome", (-0.80, -0.52, 2.18),
                             (0.52, 0.38, 0.62), m["rust"]))
    parts.append(rig.add_box("TomePages", (-0.80, -0.56, 2.18),
                             (0.44, 0.34, 0.50), m["parchment"]))
    return parts


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

BUILDERS = {
    "snail": build_snail,
    "hare": build_hare,
    "grotesque": build_grotesque,
    "scribe": build_scribe,
}


def render_species(name, frame_px):
    rig.clear_scene()
    rig.setup_render(frame_px=frame_px, subject_height_m=1.0,
                     frame_height_m=frame_m(frame_px))
    # Same ink treatment as the hero, so the cast matches: outline plus
    # colour boundaries, no creases. See rig_common.set_ink().
    rig.set_ink(crease=False, material_boundary=True, thickness=0.8)

    merged = rig.join_parts(BUILDERS[name](), f"Enemy_{name}")
    pivot = rig.group_under_pivot([merged], f"{name}Pivot")

    out_dir = rig.sprite_dir("enemy")
    rig.render_sheet(pivot, out_dir, f"enemy_{name}_idle", start_yaw_deg=45.0)
    print(f"[enemy] {name} -> {out_dir}")


def main():
    only = os.environ.get("ONLY")
    for name, frame_px in SPECIES.items():
        if only and name != only:
            continue
        render_species(name, frame_px)


if __name__ == "__main__":
    main()
