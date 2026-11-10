"""
Enemies: standard, elite and boss.

GDD, Player baseline: "Enemy HP: standard / elite / boss  40 / 120 / 1,200".
GDD, Room-Based Combat: rooms 1-6 combat, room 7 elite, room 8 boss.

Checked against the anchor asset (pipeline/player.py) for scale, outline
weight, light direction and palette, as the GDD requires.

Design rule for enemies: they are built from the SAME palette as the player
but inverted in emphasis. The player is a cool cloak with a warm Ember belt;
enemies are warm-dark bodies with Blood Rust accents and no Ember at all. That
keeps "who is on my side" readable at a glance in a crowded room.

Hostile Magenta appears NOWHERE on an enemy body - it belongs to enemy
bullets alone, which is what makes bullets readable against a wave of enemies.

Run:
    blender -b --python pipeline/enemy.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

# Frame size and metres-per-frame for each tier. Bigger tiers get bigger
# frames so the sprite never crops; the metres-per-frame figure is scaled with
# the body so all three render at a consistent pixels-per-metre.
#
# The anchor is 2.00 m of body in a 3.90 m frame at 128 px. Holding that same
# ratio (body = 0.513 of frame height) gives each tier the same visual weight
# per metre, so an elite really does look 1.3x a standard rather than just
# being drawn bigger.
ANCHOR_BODY_M = 2.00
ANCHOR_FRAME_M = 3.90
ANCHOR_FRAME_PX = 128

TIERS = {
    # name:      (body height m, frame px)
    "standard": (1.70, 128),
    "elite": (2.25, 160),
    "boss": (3.60, 256),
}


def frame_height_for(body_m: float, frame_px: int) -> float:
    """
    Metres covered by the frame, so that pixels-per-metre matches the anchor.

    The anchor renders ANCHOR_FRAME_M metres across ANCHOR_FRAME_PX pixels.
    Hold that px/m constant and a frame of frame_px pixels covers
    frame_px / (ANCHOR_FRAME_PX / ANCHOR_FRAME_M) metres.
    """
    px_per_m = ANCHOR_FRAME_PX / ANCHOR_FRAME_M
    return frame_px / px_per_m


def build_enemy(tier: str, body_m: float):
    """
    A hunched, armoured brute. Low-poly, same facet language as the player.

    Shape language, chosen so the three tiers read apart in a silhouette:
      standard - hunched, narrow, one head spike
      elite    - broader shoulders, horned helm, shoulder plates
      boss     - all of the above plus a crown of spikes and a wider stance
    """
    is_elite = tier == "elite"
    is_boss = tier == "boss"

    # ---- materials -------------------------------------------------------
    #
    # DESIGN DECISION worth reviewing. The GDD palette table assigns a swatch
    # to floors, walls, bullets and UI, but not to enemy bodies. The obvious
    # first choice, Crypt Stone, is wrong: Crypt Stone IS the floor tile, so
    # a Crypt Stone enemy standing on a Crypt Stone floor nearly vanishes.
    # Rendering it proved that - the first pass came out as a black smudge.
    # Stone Light is taken by walls and destructible cover, with the same
    # problem against cover.
    #
    # So enemy bodies are Blood Rust. It is the one swatch not used by any
    # large surface, it is not Ember (which is the player's accent) and it is
    # not Hostile Magenta (reserved for bullets). It also carries the right
    # meaning: red reads as the thing that hurts you.
    body_mat = rig.cel_material(f"Enemy{tier}Body", "8E2A2A",
                                shadow_mix=0.45, highlight_mix=0.20)
    # Armour plates in Stone Light. On a figure, against a Blood Rust body,
    # these read as armour rather than as wall.
    plate_mat = rig.cel_material(f"Enemy{tier}Plate", "4E4458",
                                 shadow_mix=0.40, highlight_mix=0.26)
    # Darker rust for straps and bands, so the accent is a value step rather
    # than a second hue.
    accent_mat = rig.cel_material(f"Enemy{tier}Accent", "8E2A2A",
                                  shadow_mix=0.0, highlight_mix=0.42)
    dark_mat = rig.cel_material(f"Enemy{tier}Dark", "120E1A",
                                shadow_mix=0.0, highlight_mix=0.16)
    bone_mat = rig.cel_material(f"Enemy{tier}Bone", "D8C8A8",
                                shadow_mix=0.48, highlight_mix=0.15)

    # Everything below is authored against a 1.0 m reference and scaled at the
    # end, so one body of code covers all three tiers.
    s = body_m / 1.70
    parts = []

    def box(name, loc, size, mat, rot=(0, 0, 0)):
        parts.append(rig.add_box(name,
                                 (loc[0] * s, loc[1] * s, loc[2] * s),
                                 (size[0] * s, size[1] * s, size[2] * s),
                                 mat, rot))

    def cone(name, loc, r1, r2, d, mat, rot=(0, 0, 0), verts=8):
        parts.append(rig.add_cone(name,
                                  (loc[0] * s, loc[1] * s, loc[2] * s),
                                  r1 * s, r2 * s, d * s, mat, verts, rot))

    def sphere(name, loc, r, mat, seg=8, rings=6):
        parts.append(rig.add_sphere(name,
                                    (loc[0] * s, loc[1] * s, loc[2] * s),
                                    r * s, mat, seg, rings))

    shoulder_w = 0.50 if not (is_elite or is_boss) else 0.62

    # ---- legs ------------------------------------------------------------
    stance = 0.17 if not is_boss else 0.26
    for side, x in (("L", -stance), ("R", stance)):
        box(f"Thigh{side}", (x, 0.02, 0.38), (0.21, 0.23, 0.50), body_mat)
        box(f"Shin{side}", (x, -0.04, 0.12), (0.19, 0.25, 0.28), dark_mat)
        box(f"Claw{side}", (x, -0.19, 0.045), (0.20, 0.14, 0.09), bone_mat)

    # ---- torso -----------------------------------------------------------
    # Hunched: the chest is pushed forward and the shoulders ride high, so the
    # silhouette leans at the player.
    cone("Torso", (0.0, 0.03, 0.88), 0.30, 0.38, 0.52, body_mat)
    box("Chest", (0.0, -0.10, 1.10), (shoulder_w, 0.30, 0.34), plate_mat)

    # Blood Rust chest band - the enemy's single clearest accent, placed where
    # the player's Ember belt sits so the two read as opposites.
    box("ChestBand", (0.0, -0.245, 1.07), (shoulder_w * 0.82, 0.07, 0.11),
        accent_mat)

    # ---- shoulders -------------------------------------------------------
    for side, x in (("L", -1.0), ("R", 1.0)):
        sx = x * (shoulder_w * 0.5 + 0.07)
        if is_elite or is_boss:
            cone(f"Pauldron{side}", (sx, -0.02, 1.26), 0.20, 0.10, 0.20,
                 plate_mat)
            cone(f"Spike{side}", (sx, -0.02, 1.42), 0.07, 0.015, 0.20,
                 accent_mat)
        else:
            box(f"Shoulder{side}", (sx, -0.02, 1.20), (0.17, 0.21, 0.17),
                plate_mat)

    # ---- arms ------------------------------------------------------------
    for side, x in (("L", -1.0), ("R", 1.0)):
        sx = x * (shoulder_w * 0.5 + 0.06)
        box(f"Arm{side}", (sx, -0.12, 0.98), (0.15, 0.19, 0.42), body_mat)
        box(f"Fist{side}", (sx, -0.19, 0.76), (0.18, 0.20, 0.17), dark_mat)

    # ---- head ------------------------------------------------------------
    box("Neck", (0.0, 0.0, 1.30), (0.16, 0.16, 0.10), dark_mat)
    sphere("Skull", (0.0, -0.05, 1.44), 0.19, plate_mat)
    # A dark visor slot with Blood Rust eyes - the mirror of the player's
    # Ember eyes in a dark hood.
    box("Visor", (0.0, -0.195, 1.45), (0.26, 0.06, 0.09), dark_mat)
    for side, x in (("L", -0.07), ("R", 0.07)):
        box(f"Eye{side}", (x, -0.225, 1.45), (0.05, 0.03, 0.035), accent_mat)

    # Horns. One small spike for a standard, a full horned helm above that.
    if is_elite or is_boss:
        for side, x in (("L", -1.0), ("R", 1.0)):
            cone(f"Horn{side}", (x * 0.15, 0.02, 1.64), 0.065, 0.015, 0.30,
                 bone_mat, rot=(math.radians(-18.0), 0.0, x * math.radians(26.0)))
    else:
        cone("Crest", (0.0, 0.03, 1.60), 0.07, 0.015, 0.20, bone_mat)

    # A boss gets a crown of spikes so its silhouette is unmistakable at the
    # moment the room 8 door opens.
    if is_boss:
        for i in range(6):
            a = math.pi * (i / 5.0) - math.pi * 0.5
            cone(f"Crown{i}", (math.sin(a) * 0.20, 0.06 + math.cos(a) * 0.12,
                               1.62), 0.045, 0.012, 0.26, accent_mat,
                 rot=(math.radians(-10.0), 0.0, 0.0))

    return parts


def main():
    for tier, (body_m, frame_px) in TIERS.items():
        rig.clear_scene()
        rig.setup_render(frame_px=frame_px,
                         subject_height_m=body_m,
                         frame_height_m=frame_height_for(body_m, frame_px))

        parts = build_enemy(tier, body_m)
        pivot = rig.group_under_pivot(parts, f"Enemy{tier}Pivot")

        out_dir = rig.sprite_dir("enemy")
        rig.render_sheet(pivot, out_dir, f"enemy_{tier}_idle",
                         start_yaw_deg=45.0)
        print(f"[enemy] {tier} written to {out_dir}")


if __name__ == "__main__":
    main()
