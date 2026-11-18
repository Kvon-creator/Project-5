"""
ANCHOR ASSET - the Nib Knight.

Reference: docs/reference/hero-nib-knight.png. The instruction was "this is
how the hero should look, only reference this", so that single image governs
- where it disagrees with the GDD, it wins.

It disagrees in one place worth naming. The GDD's avoid list bans "Chibi or
cartoon proportions", but the reference knight is unmistakably stocky: an
oversized great helm on a short, broad body. That is a deliberate silhouette
choice, not a slip, and it is what makes him read at 64 px. The reference
wins; this note exists so nobody "fixes" it later by citing the GDD.

Design, read off the reference:
  - great helm roughly a third of total height, closed, single eye slit
  - steel plate kept almost colourless, so the two accents own the eye
  - ember plume swept BACK off the helm - the facing cue at small size
  - tattered parchment cape
  - a spear whose head is a fountain-pen nib, charged teal

Exactly two points of colour on him: ember plume, teal nib. Everything else
is steel and parchment. That is why he never gets lost in a room full of
violet creatures.

Run:
    blender -b --python pipeline/player.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

FRAME_PX = 128

# Stocky. The previous hooded figure was 2.0 m of ordinary human proportion;
# this knight is shorter and wider, with the mass in the helm and chest.
BODY_HEIGHT_M = 1.60

# Metres the 128 px frame covers. Tuned so the knight lands on the anchor
# spec of ~64 px tall. Verify with: python3 pipeline/check_anchor.py
FRAME_HEIGHT_M = 3.80

# The camera sits on -Y, so a model facing -Y renders facing screen-down.
# Yawing +45 deg turns that to screen down-right, which is the anchor pose.
ANCHOR_YAW_DEG = 45.0


def build_player():
    # ---- materials -------------------------------------------------------
    # Steel is deliberately low-chroma and mid-value. In the reference the
    # armour is almost grey - a stage for the plume and the nib, not a
    # feature competing with them.
    steel = rig.cel_material("KnightSteel", "868178",
                             shadow_mix=0.26, highlight_mix=0.34)
    steel_dark = rig.cel_material("KnightSteelDark", "554F59",
                                  shadow_mix=0.22, highlight_mix=0.30)
    # Cape and surcoat in parchment, tying the hero to the manuscript theme.
    cloth = rig.cel_material("KnightCloth", "E2C5A8",
                             shadow_mix=0.30, highlight_mix=0.16)
    ember = rig.cel_material("KnightPlume", "F06A2A",
                             shadow_mix=0.35, highlight_mix=0.28)
    dark = rig.cel_material("KnightDark", "18030A",
                            shadow_mix=0.0, highlight_mix=0.14)
    # The nib charge is FLAT emission, not cel-shaded. It has to be the same
    # teal from all 8 angles - it is what the player's eye tracks, and a
    # shaded version would go dim whenever he faced away from the key light.
    teal = rig.flat_material("NibTeal", "35D6C4", strength=2.2)
    teal_soft = rig.flat_material("NibTealSoft", "98E5DD", strength=1.3)

    parts = []

    # ---- legs ------------------------------------------------------------
    # Short and planted wide. The reference stance is broad; that reads as
    # weight, which is what stops a big helm from looking top-heavy.
    for side, x in (("L", -0.17), ("R", 0.17)):
        parts.append(rig.add_box(f"Thigh{side}", (x, 0.02, 0.33),
                                 (0.20, 0.21, 0.30), steel_dark))
        parts.append(rig.add_box(f"Greave{side}", (x, -0.01, 0.13),
                                 (0.18, 0.19, 0.26), steel))
        parts.append(rig.add_box(f"Sabaton{side}", (x, -0.09, 0.035),
                                 (0.19, 0.30, 0.09), steel_dark))

    # ---- fauld (the armoured skirt) --------------------------------------
    parts.append(rig.add_cone("Fauld", (0.0, 0.0, 0.52),
                              radius1=0.34, radius2=0.26, depth=0.22,
                              material=steel, verts=10))

    # ---- breastplate -----------------------------------------------------
    # Barrel-chested, widening upward to the shoulders.
    parts.append(rig.add_cone("Breastplate", (0.0, 0.0, 0.80),
                              radius1=0.25, radius2=0.30, depth=0.40,
                              material=steel, verts=10))
    # A darker placard across the chest, for a value break mid-torso.
    parts.append(rig.add_box("Placard", (0.0, -0.26, 0.74),
                             (0.34, 0.09, 0.20), steel_dark))

    # ---- pauldrons and arms ----------------------------------------------
    for side, x in (("L", -1.0), ("R", 1.0)):
        parts.append(rig.add_sphere(f"Pauldron{side}", (x * 0.33, 0.0, 0.93),
                                    radius=0.15, material=steel,
                                    segments=10, rings=6))
        parts.append(rig.add_box(f"Arm{side}", (x * 0.34, -0.04, 0.75),
                                 (0.15, 0.16, 0.30), steel_dark))

    # ---- gorget and great helm -------------------------------------------
    parts.append(rig.add_cylinder("Gorget", (0.0, 0.0, 1.07),
                                  radius=0.15, depth=0.10,
                                  material=steel_dark, verts=10))

    # A flat-topped cylinder rather than a sphere: the reference helm has
    # hard planes and a flat crown, and a cylinder keeps the ink outline
    # reading as straight edges instead of a soft blob.
    parts.append(rig.add_cylinder("Helm", (0.0, -0.01, 1.30),
                                  radius=0.235, depth=0.40,
                                  material=steel, verts=10))
    parts.append(rig.add_cylinder("HelmCrown", (0.0, -0.01, 1.51),
                                  radius=0.225, depth=0.06,
                                  material=steel_dark, verts=10))
    # Tapered jaw, so the helm is not a plain can.
    parts.append(rig.add_cone("HelmJaw", (0.0, -0.02, 1.12),
                              radius1=0.17, radius2=0.235, depth=0.14,
                              material=steel, verts=10))

    # Eye slit. One dark horizontal band is the entire face - at 64 px that
    # is all that survives, and it is enough to say where he is looking.
    parts.append(rig.add_box("EyeSlit", (0.0, -0.225, 1.33),
                             (0.30, 0.06, 0.055), dark))
    # A raised rib down the helm's centre line, to catch a highlight.
    parts.append(rig.add_box("HelmRib", (0.0, -0.215, 1.27),
                             (0.05, 0.07, 0.30), steel_dark))

    # ---- plume -----------------------------------------------------------
    # Swept BACK and up. Like the hood peak on the old design, this is the
    # strongest facing cue at sprite size - much stronger than the eye slit,
    # which is only a couple of pixels wide.
    for i, (loc, size, tilt) in enumerate((
            ((0.0, 0.10, 1.60), (0.13, 0.20, 0.17), 0.0),
            ((0.0, 0.22, 1.69), (0.12, 0.22, 0.15), 18.0),
            ((0.0, 0.36, 1.73), (0.10, 0.22, 0.12), 36.0),
            ((0.0, 0.49, 1.71), (0.08, 0.20, 0.09), 54.0))):
        parts.append(rig.add_box(f"Plume{i}", loc, size, ember,
                                 rotation=(math.radians(tilt), 0.0, 0.0)))
    parts.append(rig.add_cylinder("PlumeSocket", (0.0, 0.02, 1.55),
                                  radius=0.06, depth=0.09,
                                  material=steel_dark, verts=8))

    # ---- cape ------------------------------------------------------------
    # Hangs off the shoulders and flares back. Built from a few slabs at
    # different lengths so the hem is ragged - the reference cape is torn,
    # and a clean hem would read as a tidy cloak instead.
    for i, (loc, size, tilt) in enumerate((
            ((0.0, 0.26, 0.74), (0.62, 0.10, 0.80), 10.0),
            ((-0.20, 0.30, 0.52), (0.26, 0.09, 0.56), 16.0),
            ((0.22, 0.31, 0.58), (0.24, 0.09, 0.66), 13.0),
            ((0.04, 0.34, 0.34), (0.34, 0.08, 0.40), 22.0))):
        parts.append(rig.add_box(f"Cape{i}", loc, size, cloth,
                                 rotation=(math.radians(tilt), 0.0, 0.0)))
    parts.append(rig.add_cylinder("Clasp", (0.0, 0.14, 1.03),
                                  radius=0.07, depth=0.06,
                                  material=ember, verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))

    # ---- the nib spear ---------------------------------------------------
    # Held forward along -Y so it swings with the facing.
    parts.append(rig.add_cylinder("Shaft", (0.26, -0.55, 0.74),
                                  radius=0.038, depth=1.10,
                                  material=steel_dark, verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    parts.append(rig.add_box("Grip", (0.26, -0.18, 0.74),
                             (0.09, 0.22, 0.09), dark))
    parts.append(rig.add_cone("Ferrule", (0.26, -1.02, 0.74),
                              radius1=0.055, radius2=0.085, depth=0.14,
                              material=steel, verts=8,
                              rotation=(math.radians(-90.0), 0.0, 0.0)))

    # The nib: a flattened, tapered blade - a real fountain-pen nib rather
    # than a spearhead. Squashed on Z so it is a blade, not a cone. This is
    # the single most important silhouette read on the hero.
    nib = rig.add_cone("Nib", (0.26, -1.24, 0.74),
                       radius1=0.145, radius2=0.012, depth=0.42,
                       material=steel, verts=10,
                       rotation=(math.radians(-90.0), 0.0, 0.0))
    nib.scale = (1.0, 1.0, 0.42)
    parts.append(nib)
    parts.append(rig.add_box("NibSlit", (0.26, -1.26, 0.755),
                             (0.022, 0.30, 0.03), dark))
    parts.append(rig.add_cylinder("NibHole", (0.26, -1.13, 0.755),
                                  radius=0.034, depth=0.05,
                                  material=dark, verts=8))

    # Teal charge at the point: a bright core plus a few trailing sparks.
    # No bloom - the avoid list bans glow that could hide a bullet, and this
    # sits exactly where the player is looking.
    core = rig.add_cone("NibGlow", (0.26, -1.45, 0.74),
                        radius1=0.115, radius2=0.0, depth=0.30,
                        material=teal, verts=8,
                        rotation=(math.radians(-90.0), 0.0, 0.0))
    core.scale = (1.0, 1.0, 0.5)
    parts.append(core)
    for i, (off, r) in enumerate(((-1.38, 0.072), (-1.57, 0.050),
                                  (-1.70, 0.032))):
        parts.append(rig.add_sphere(f"Spark{i}", (0.26, off, 0.745), r,
                                    teal_soft, segments=7, rings=5))

    return parts


def main():
    rig.clear_scene()
    rig.setup_render(frame_px=FRAME_PX,
                     subject_height_m=BODY_HEIGHT_M,
                     frame_height_m=FRAME_HEIGHT_M)
    # Outline and colour boundaries only. See set_ink() for why creases are
    # off for characters.
    rig.set_ink(crease=False, material_boundary=True, thickness=0.8)

    # Join first: one mesh means one outline. See join_parts().
    merged = rig.join_parts(build_player(), "NibKnight")
    pivot = rig.group_under_pivot([merged], "PlayerPivot")

    out_dir = rig.sprite_dir("player")
    rig.render_sheet(pivot, out_dir, "player_idle",
                     start_yaw_deg=ANCHOR_YAW_DEG)
    print("[player] anchor asset written to", out_dir)


if __name__ == "__main__":
    main()
