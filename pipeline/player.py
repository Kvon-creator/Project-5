"""
ANCHOR ASSET - the player character's idle sprite.

GDD, Anchor asset:
    The player character's idle sprite, facing down-right, about 64 px tall in
    a 128 x 128 frame. Every other asset is checked against it for scale,
    outline weight, light direction and palette before it goes in the game.
    It is drawn first, by November 18.

So this file runs first and everything else is tuned to match its output.

Design: a hooded dungeon-delver. Low-poly, blocky, built from primitives.
Ember (#F06A2A) is the player's accent colour per the GDD palette table, used
on the belt, hood trim and weapon muzzle so the player reads instantly against
Crypt Stone floors. Nothing on the player is magenta or pink - that is
reserved for enemy bullets.

Run:
    blender -b --python pipeline/player.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

# --------------------------------------------------------------------------
# Scale
# --------------------------------------------------------------------------

FRAME_PX = 128

# Model height in metres. A human-scale character.
BODY_HEIGHT_M = 2.0

# How many metres the 128 px frame covers, top to bottom.
#
# This is NOT 4.0, and the reason matters. The camera looks down at 55 deg, so
# a vertical object is foreshortened: it projects to height * cos(55) = 0.57 of
# its world height. A 2 m character therefore paints about 1.15 m of screen
# height. To land that on the 64 px the anchor spec asks for, the frame has to
# cover ~2.3 m rather than 4 m.
#
# The GDD's "1 m = 32 px" is a GAMEPLAY-space rule for the 2D game (barrel
# radius 3 m = 96 px, and so on). It is not a claim about the projection. Those
# two numbers live in different spaces and both are correct.
#
# Verify with:  python3 pipeline/check_anchor.py
FRAME_HEIGHT_M = 3.90

# Facing. The camera sits on -Y, so a model whose forward is -Y renders facing
# straight at the viewer (screen "down"). Yawing +45 deg turns that forward to
# (+X, -Y), which is screen down-right - the anchor pose.
ANCHOR_YAW_DEG = 45.0


def build_player():
    """Return every object making up the player, for parenting to one pivot."""
    # ---- materials -------------------------------------------------------
    # The cloak is the biggest shape, so it carries the character's value. Kept
    # in the Stone Light family: cool and mid-dark, so Ember accents pop and
    # the silhouette still separates from the near-black Abyss background.
    cloak_mat = rig.cel_material("PlayerCloak", "4E4458",
                                 shadow_mix=0.55, highlight_mix=0.22)
    # The tunic under the cloak, a step darker for depth.
    tunic_mat = rig.cel_material("PlayerTunic", "2B2335",
                                 shadow_mix=0.45, highlight_mix=0.28)
    # Ember accents: belt, hood trim, muzzle.
    accent_mat = rig.cel_material("PlayerAccent", "F06A2A",
                                  shadow_mix=0.40, highlight_mix=0.25)
    # Skin/face, in the Bone family. Mostly in hood shadow.
    bone_mat = rig.cel_material("PlayerBone", "D8C8A8",
                                shadow_mix=0.50, highlight_mix=0.15)
    # The hood interior and boots: nearly Abyss, reads as a dark void.
    dark_mat = rig.cel_material("PlayerDark", "120E1A",
                                shadow_mix=0.0, highlight_mix=0.18)
    # Player shots are Spirit Teal, so the weapon's energy cell matches - the
    # player can see where their own damage comes from.
    teal_mat = rig.flat_material("PlayerTeal", "35D6C4", strength=1.4)

    parts = []

    # Proportions note. At a 45 deg camera every vertical measurement loses
    # ~29% on screen, so the model is built TALLER and NARROWER than it would
    # be for a side view. The first pass used a 0.52 m cloak hem on a 2 m body
    # and rendered as a bell. Keeping the widest point at ~0.40 m against a
    # 2.05 m height gives a 1 : 2.5 width-to-height ratio, which still reads
    # as a figure after foreshortening.

    # ---- legs and boots --------------------------------------------------
    # Mostly hidden by the cloak. They exist to break the bottom edge of the
    # silhouette so the character does not terminate in a flat skirt.
    # Boots are pushed FORWARD (-Y) as well as down. At a 45 deg camera a
    # boot tucked under the hem is invisible; offsetting it toward the
    # viewer puts it in front of the cloak where it breaks the silhouette.
    for side, x in (("L", -0.13), ("R", 0.13)):
        parts.append(rig.add_box(f"Leg{side}", (x, -0.04, 0.26),
                                 (0.17, 0.18, 0.52), tunic_mat))
        parts.append(rig.add_box(f"Boot{side}", (x, -0.17, 0.07),
                                 (0.20, 0.34, 0.15), dark_mat))
        # Ember toe-cap, tying the boots to the belt so the accent colour
        # appears at both ends of the figure instead of only the middle.
        parts.append(rig.add_box(f"Toe{side}", (x, -0.32, 0.055),
                                 (0.18, 0.06, 0.11), accent_mat))

    # ---- cloak -----------------------------------------------------------
    # The main mass. Tapered, but far closer to a column than a cone, so the
    # shoulders and head stay the widest readable landmarks.
    parts.append(rig.add_cone("Cloak", (0.0, 0.04, 0.66),
                              radius1=0.40, radius2=0.26, depth=1.16,
                              material=cloak_mat, verts=8))

    # A shallow flare at the hem catches the ink outline as its own line, so
    # the bottom of the cloak separates from the legs.
    parts.append(rig.add_cone("CloakHem", (0.0, 0.04, 0.12),
                              radius1=0.43, radius2=0.39, depth=0.14,
                              material=cloak_mat, verts=8))

    # The cloak hangs open at the front: a wedge of darker tunic down the
    # middle gives the flat front face something to read against.
    parts.append(rig.add_box("TunicFront", (0.0, -0.28, 0.78),
                             (0.22, 0.10, 0.96), tunic_mat))

    # ---- belt ------------------------------------------------------------
    # Ember, the player's loudest accent. Sits at the waist near the sprite's
    # centre, which is the part of a 64 px character the eye lands on first.
    # Made deliberately chunky: at 64 px a 0.10 m band is barely one pixel
    # after foreshortening, and the first render lost it entirely. 0.17 m
    # survives, and the slight overhang past the cloak catches an ink line
    # top and bottom so it reads as a band rather than a colour change.
    parts.append(rig.add_cylinder("Belt", (0.0, 0.04, 1.00),
                                  radius=0.375, depth=0.17,
                                  material=accent_mat, verts=8))
    parts.append(rig.add_box("Buckle", (0.0, -0.345, 1.00),
                             (0.14, 0.08, 0.15), bone_mat))

    # ---- torso and shoulders ---------------------------------------------
    parts.append(rig.add_box("Torso", (0.0, 0.0, 1.38),
                             (0.40, 0.27, 0.62), tunic_mat))

    # Mantle over the shoulders. Kept only slightly wider than the torso and
    # pulled DOWN off the head, so there is clear sky between the shoulder
    # line and the hood - that gap is what makes the head read as a head.
    parts.append(rig.add_cone("Mantle", (0.0, 0.0, 1.60),
                              radius1=0.365, radius2=0.25, depth=0.26,
                              material=cloak_mat, verts=8))
    parts.append(rig.add_cone("MantleTrim", (0.0, 0.0, 1.49),
                              radius1=0.385, radius2=0.365, depth=0.06,
                              material=accent_mat, verts=8))

    # ---- neck, head and hood ---------------------------------------------
    # Build order matters here. The camera looks down at 45 deg, so anything
    # that does not sit UNDER a hood surface will be seen from above. The
    # first pass put a bone-coloured head sphere at the top of the body with
    # a back-swept hood behind it, and the render showed a pale disc on top
    # of the head like an open lid. The hood now encloses the skull from
    # above and behind, and the face reads through a front opening only.
    parts.append(rig.add_cylinder("Neck", (0.0, -0.01, 1.73),
                                  radius=0.085, depth=0.13,
                                  material=dark_mat, verts=8))

    # Head, pushed slightly forward so it sits inside the hood opening rather
    # than centred under the dome.
    parts.append(rig.add_sphere("Head", (0.0, -0.05, 1.86), radius=0.155,
                                material=bone_mat, segments=10, rings=6))

    # Hood dome: a squashed sphere covering the skull from above and behind.
    # This is the part that stops the camera seeing the top of the head.
    hood_dome = rig.add_sphere("HoodDome", (0.0, 0.015, 1.90), radius=0.215,
                               material=cloak_mat, segments=10, rings=7)
    hood_dome.scale = (1.0, 1.08, 0.95)
    parts.append(hood_dome)

    # Back-swept cowl. Kept LOW and close to the dome. An earlier pass used a
    # tall tilted spike plus a front brim here; at 45 deg the spike read as an
    # ear growing out of the side of the head, and the brim covered the face
    # opening entirely. A low cowl breaks the back of the silhouette without
    # competing with the skull, and leaves the face clear.
    cowl = rig.add_sphere("HoodCowl", (0.0, 0.17, 1.82), radius=0.15,
                          material=cloak_mat, segments=8, rings=6)
    cowl.scale = (1.0, 1.25, 0.78)
    parts.append(cowl)

    # Face void: a dark disc filling the hood opening, facing forward (-Y).
    # Keeping the face dark keeps the Ember belt the brightest thing on the
    # character, which is what the eye should land on first.
    parts.append(rig.add_cylinder("HoodVoid", (0.0, -0.175, 1.855),
                                  radius=0.145, depth=0.07,
                                  material=dark_mat, verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))

    # Two small Ember eye-lights inside the void. At 64 px these resolve to
    # roughly one pixel each, which is exactly enough to tell the player
    # which way the character is looking without drawing a face.
    for side, x in (("L", -0.05), ("R", 0.05)):
        parts.append(rig.add_box(f"Eye{side}", (x, -0.205, 1.865),
                                 (0.035, 0.02, 0.025), accent_mat))

    # ---- arms and weapon -------------------------------------------------
    # Left arm hangs at the side; right arm is extended forward with the
    # weapon. The asymmetry is deliberate - it tells the player which way
    # they are aiming even before the sprite direction registers.
    parts.append(rig.add_box("ArmL", (-0.345, -0.02, 1.28),
                             (0.15, 0.17, 0.50), cloak_mat))
    parts.append(rig.add_box("ArmR", (0.29, -0.18, 1.40),
                             (0.15, 0.42, 0.17), cloak_mat,
                             rotation=(0.0, 0.0, math.radians(-8.0))))
    parts.append(rig.add_box("HandR", (0.27, -0.40, 1.38),
                             (0.14, 0.13, 0.14), bone_mat))

    # Weapon: a stubby arcane sidearm pointing along -Y, so it swings with
    # the facing. Spirit Teal cell, because Spirit Teal is what the player's
    # shots are - the gun and its bullets match.
    parts.append(rig.add_box("WeaponBody", (0.27, -0.56, 1.38),
                             (0.13, 0.32, 0.16), dark_mat))
    parts.append(rig.add_box("WeaponCell", (0.27, -0.52, 1.48),
                             (0.08, 0.13, 0.06), teal_mat))
    parts.append(rig.add_cylinder("Muzzle", (0.27, -0.75, 1.38),
                                  radius=0.07, depth=0.11,
                                  material=accent_mat, verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))

    return parts


def main():
    rig.clear_scene()
    rig.setup_render(frame_px=FRAME_PX,
                     subject_height_m=BODY_HEIGHT_M,
                     frame_height_m=FRAME_HEIGHT_M)

    parts = build_player()
    pivot = rig.group_under_pivot(parts, "PlayerPivot")

    out_dir = rig.sprite_dir("player")
    rig.render_sheet(pivot, out_dir, "player_idle",
                     start_yaw_deg=ANCHOR_YAW_DEG)

    print("[player] anchor asset written to", out_dir)


if __name__ == "__main__":
    main()
