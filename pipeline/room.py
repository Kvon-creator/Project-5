"""
The room - a scriptorium chamber, built to match docs/reference/
room-painted-interior.png.

This is a DIFFERENT approach from the tilemap the scaffold shipped with, and
the reference is the reason. That painted room is not a grid of square tiles:
it is a shallow diorama - a floor quadrilateral with three walls standing
around it, ornament concentrated on the walls, and the floor left plain so
things moving across it stay readable. You cannot build that out of 64 px
square tiles without losing exactly the thing that makes it look drawn.

So a room is rendered as ONE image, and Godot gets a background sprite plus
collision shapes. The GDD's "10 hand-built layouts" become 10 of these.
That is also less engine work, not more: no TileSet, no atlas, no per-cell
data.

    blender -b --python pipeline/room.py
"""

import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402
import rig_common as rig  # noqa: E402

# --------------------------------------------------------------------------
# Measured palette, from pipeline/extract_palette.py over the references
# --------------------------------------------------------------------------

STONE_LIT = "8A8088"      # floor in light - the room's dominant value
STONE_MID = "776B70"      # wall faces
STONE_SHADOW = "554F59"   # wall shadow, floor away from light
INK_VIOLET = "3C2C39"     # deep shadow, recesses
INK_BLACK = "18030A"      # ink pools, outlines
PARCHMENT = "E2C5A8"      # paper, gilt filigree
CANDLE_WARM = "BE9E91"
FLAME_GLOW = "E9A765"     # what a lit surface leans toward
COLD_SHADOW = "2A2038"    # what an unlit surface leans toward
GILT = "C8A24E"           # the gold vine work
WOOD_RUST = "70280C"      # door timber, warm red-brown
EMBER = "F06A2A"          # candle flame

# --------------------------------------------------------------------------
# Room dimensions, in metres. 1 m = 32 px in gameplay space.
# --------------------------------------------------------------------------

ROOM_W = 36.0
# Depth is set by how the floor PROJECTS, not by how it measures.
#
# At a 45 deg camera a floor's on-screen height is depth * sin(45) = 0.71 of
# its world depth, so a 20 m room painted a 964 x 379 px play area - a 2.5:1
# strip. In that strip the Shockwave's 150 px radius covers 79% of the
# available height, which would make the GDD's most expensive ability close
# to a free room-clear. 28 m projects to roughly 964 x 530, near 16:9, and
# the GDD's numbers mean what they were balanced to mean.
ROOM_D = 28.0
WALL_H = 4.2
WALL_T = 1.0

# Matches the character rig, and it has to: a room shot at a different
# elevation from the sprites standing in it reads as two separate pictures.
#
# The floor's vertical footprint is depth * sin(elevation), NOT cos - a
# higher camera sees MORE floor, not less. At 58 deg a 20 m floor paints
# 17 m of frame and shoves the walls off the top edge, which is exactly what
# the first render did. At 45 deg it paints 14.1 m and the walls fit.
ROOM_ELEVATION_DEG = 45.0

RENDER_W, RENDER_H = 1152, 640

# Where the wall candles stand. Shared by the geometry and the point lights,
# so a flame and its light can never drift apart.
FLOOR_LIGHTS = [
    (-ROOM_W * 0.30, ROOM_D * 0.30),
    (ROOM_W * 0.32, ROOM_D * 0.26),
    (-ROOM_W * 0.34, -ROOM_D * 0.28),
    (ROOM_W * 0.30, -ROOM_D * 0.30),
]

CANDLE_SPOTS = {
    "A": (-ROOM_W * 0.5 + 2.2, ROOM_D * 0.5 - 0.2),
    "B": (ROOM_W * 0.5 - 2.2, ROOM_D * 0.5 - 0.2),
    "C": (-ROOM_W * 0.5 + 0.3, -ROOM_D * 0.18),
    "D": (ROOM_W * 0.5 - 0.3, ROOM_D * 0.10),
}


def mat(name, hex_colour, shadow=0.42, light=0.22, bands=6, grain=0.13,
        grain_scale=9.0, warm=CANDLE_WARM, cool=None, joints=0.0,
        joint_scale=6.0):
    """
    Environment surfaces use the painterly shader: mottled, softly banded,
    and leaning WARM in the lit band. Characters keep the hard 3-band cel
    look, which is what separates figures from scenery at a glance.
    """
    return rig.painterly_material(name, hex_colour, shadow_mix=shadow,
                                  highlight_mix=light, bands=bands,
                                  grain=grain, grain_scale=grain_scale,
                                  warm_hex=warm, cool_hex=cool,
                                  joints=joints, joint_scale=joint_scale)


def flat(name, hex_colour, strength=1.0):
    return rig.flat_material(name, hex_colour, strength=strength)


# --------------------------------------------------------------------------
# Floor
# --------------------------------------------------------------------------

def build_floor(parts):
    """
    Plain grey-violet stone with shallow flagstone seams and a rune inlay.

    Kept deliberately quiet. The avoid list in the GDD bans busy, high
    contrast floors where bullets travel, and the arena reference confirms
    it - its mandala inlay is barely a value step above the stone. All the
    floor's interest comes from light and from ink, not from pattern.
    """
    stone = mat("FloorStone", STONE_LIT, bands=7, grain=0.26,
                grain_scale=5.0, shadow=0.58, light=0.55,
                warm=FLAME_GLOW, cool=COLD_SHADOW,
                joints=0.45, joint_scale=7.0)
    seam = mat("FloorSeam", STONE_MID, shadow=0.34, light=0.12,
           bands=3, grain=0.05)
    inlay = mat("FloorInlay", STONE_SHADOW, shadow=0.20, light=0.18, bands=2)

    parts.append(rig.add_box("Floor", (0, 0, -0.1), (ROOM_W, ROOM_D, 0.2),
                             stone))

    # No modelled seams: the flagstone joints come from the floor material's
    # procedural brick texture. See painterly_material(joints=...).

    # Rune inlay: concentric rings at the room's centre, like the arena
    # reference. Real annuli - the first pass drew a ring and then a filled
    # disc of floor stone on top of it, which buried every inner ring and
    # left one flat circle.
    for radius, width in ((7.6, 0.30), (6.9, 0.16), (3.6, 0.22),
                          (1.4, 0.18)):
        parts.append(rig.add_ring(f"Ring{int(radius * 10)}", (0, 0, 0.01),
                                  radius=radius, thickness=width,
                                  height=0.02, material=inlay, verts=56))

    # Eight spokes, so the inlay reads as a sigil rather than as targets.
    for i in range(8):
        a = math.tau * i / 8.0
        parts.append(rig.add_box(f"Spoke{i}",
                                 (math.cos(a) * 5.0, math.sin(a) * 5.0, 0.01),
                                 (2.8, 0.22, 0.016), inlay,
                                 rotation=(0, 0, a)))


# --------------------------------------------------------------------------
# Walls, pilasters, filigree, doors
# --------------------------------------------------------------------------

def vine_scroll(parts, tag, centre, span, height, material, facing,
                flip=False):
    """
    One gilt vine scroll: a shallow S-curve with leaves off it.

    Real illuminated-manuscript scrollwork cannot be modelled convincingly
    from primitives, but it does not need to be - at room scale what reads is
    the RHYTHM: a curving stem, a spiral terminal, leaves alternating off it.
    Built from arcs rather than straight segments, which is the difference
    between ornament and a row of boxes.
    """
    cx, cy, cz = centre
    sgn = -1.0 if flip else 1.0

    # Two opposed arcs make the S. In a "back" panel the stem runs along X;
    # in a side panel it runs along Y.
    for half in (0, 1):
        direction = 1.0 if half == 0 else -1.0
        off = span * 0.25 * direction
        if facing == "back":
            c = (cx + off, cy, cz)
            plane = "xz"
        else:
            c = (cx, cy + off, cz)
            plane = "yz"
        rig.add_arc(parts, f"{tag}S{half}", c, radius=height * 0.42,
                    start_deg=-80.0 * direction * sgn,
                    end_deg=80.0 * direction * sgn,
                    bead_radius=height * 0.055, material=material,
                    segments=9, plane=plane, squash=0.55 * direction)

    # Spiral terminals at each end.
    for end, direction in (("A", 1.0), ("B", -1.0)):
        if facing == "back":
            c = (cx + span * 0.46 * direction, cy, cz + height * 0.1)
            plane = "xz"
        else:
            c = (cx, cy + span * 0.46 * direction, cz + height * 0.1)
            plane = "yz"
        rig.add_arc(parts, f"{tag}C{end}", c, radius=height * 0.20,
                    start_deg=0.0, end_deg=300.0,
                    bead_radius=height * 0.05, material=material,
                    segments=9, plane=plane, squash=0.9)

    # Leaves alternating along the stem.
    for i in range(5):
        t = (i + 0.5) / 5.0 - 0.5
        updown = 1.0 if i % 2 == 0 else -1.0
        if facing == "back":
            loc = (cx + t * span, cy - 0.05, cz + updown * height * 0.26)
            size = (height * 0.17, 0.10, height * 0.11)
        else:
            loc = (cx - 0.05, cy + t * span, cz + updown * height * 0.26)
            size = (0.10, height * 0.17, height * 0.11)
        parts.append(rig.add_box(f"{tag}L{i}", loc, size, material,
                                 rotation=(0.0, math.radians(38.0 * updown),
                                           0.0)))


def arched_door(parts, cx, cy, facing, tag):
    """
    An arched doorway: stone surround, warm timber, dark opening.

    The GDD needs doors to read as locked or unlocked at a glance. Here the
    SURROUND is rendered into the room image (it never changes) while the
    door leaf itself is left to a separate sprite in Godot, so RoomManager
    can swap locked and open art without re-rendering the whole room.
    """
    surround = mat("DoorStone" + tag, CANDLE_WARM, shadow=0.35, light=0.28)
    void = mat("DoorVoid" + tag, INK_BLACK, shadow=0.0, light=0.08)

    w, h = 3.2, 3.4
    deep = WALL_T * 0.9
    if facing == "back":
        size_surround = (w + 0.9, deep, h + 0.5)
        size_void = (w, deep * 1.1, h)
        arch_rot = (math.radians(90), 0, 0)
    else:
        size_surround = (deep, w + 0.9, h + 0.5)
        size_void = (deep * 1.1, w, h)
        arch_rot = (math.radians(90), 0, math.radians(90))

    parts.append(rig.add_box(f"DoorSur{tag}", (cx, cy, h * 0.5 + 0.1),
                             size_surround, surround))
    parts.append(rig.add_box(f"DoorVoid{tag}", (cx, cy, h * 0.46),
                             size_void, void))
    # The arch itself.
    parts.append(rig.add_cylinder(f"Arch{tag}", (cx, cy, h * 0.92),
                                  radius=w * 0.5, depth=deep * 1.12,
                                  material=void, verts=16,
                                  rotation=arch_rot))
    parts.append(rig.add_cylinder(f"ArchSur{tag}", (cx, cy, h * 0.92),
                                  radius=w * 0.5 + 0.45, depth=deep * 0.98,
                                  material=surround, verts=16,
                                  rotation=arch_rot))

    # Timber door leaves set into the opening. The reference doors are warm
    # red-brown boards with iron bands - the only warm mass on a cool wall,
    # which is what makes a doorway read as a way out from across the room.
    timber = mat(f"Timber{tag}", WOOD_RUST, shadow=0.30, light=0.30,
                 grain=0.17, grain_scale=22.0)
    iron = mat(f"Iron{tag}", STONE_SHADOW, shadow=0.18, light=0.26)
    for i in range(4):
        t = (i + 0.5) / 4.0 - 0.5
        if facing == "back":
            loc = (cx + t * w * 0.92, cy - deep * 0.62, h * 0.46)
            size = (w * 0.21, 0.12, h * 0.90)
        else:
            loc = (cx - deep * 0.62, cy + t * w * 0.92, h * 0.46)
            size = (0.12, w * 0.21, h * 0.90)
        parts.append(rig.add_box(f"Board{tag}{i}", loc, size, timber))
    for i, dz in enumerate((h * 0.22, h * 0.70)):
        if facing == "back":
            loc = (cx, cy - deep * 0.70, dz)
            size = (w * 0.94, 0.09, h * 0.09)
        else:
            loc = (cx - deep * 0.70, cy, dz)
            size = (0.09, w * 0.94, h * 0.09)
        parts.append(rig.add_box(f"Band{tag}{i}", loc, size, iron))


def build_walls(parts):
    stone = mat("WallStone", STONE_MID, shadow=0.52, light=0.50,
                warm=FLAME_GLOW, cool=COLD_SHADOW)
    cap = mat("WallCap", STONE_SHADOW, shadow=0.30, light=0.22)
    pil = mat("Pilaster", CANDLE_WARM, shadow=0.48, light=0.42,
              warm=FLAME_GLOW, cool=COLD_SHADOW)

    hw, hd = ROOM_W * 0.5, ROOM_D * 0.5

    # Back wall (far side, +Y) and the two side walls. The near side is open
    # so the camera looks into the room.
    parts.append(rig.add_box("WallBack", (0, hd + WALL_T * 0.5, WALL_H * 0.5),
                             (ROOM_W + WALL_T * 2, WALL_T, WALL_H), stone))
    parts.append(rig.add_box("WallLeft", (-hw - WALL_T * 0.5, 0, WALL_H * 0.5),
                             (WALL_T, ROOM_D, WALL_H), stone))
    parts.append(rig.add_box("WallRight", (hw + WALL_T * 0.5, 0, WALL_H * 0.5),
                             (WALL_T, ROOM_D, WALL_H), stone))

    # Caps along the top of each wall, so the wall reads as a solid mass with
    # a lit top edge rather than a flat painted band.
    parts.append(rig.add_box("CapBack", (0, hd + WALL_T * 0.5, WALL_H + 0.18),
                             (ROOM_W + WALL_T * 2.4, WALL_T * 1.3, 0.36), cap))
    for side, x in (("L", -1), ("R", 1)):
        parts.append(rig.add_box(
            f"Cap{side}", (x * (hw + WALL_T * 0.5), 0, WALL_H + 0.18),
            (WALL_T * 1.3, ROOM_D, 0.36), cap))

    # Corner pilasters.
    for sx in (-1, 1):
        parts.append(rig.add_box(
            f"PilarB{sx}", (sx * hw, hd + WALL_T * 0.5, WALL_H * 0.52),
            (1.5, WALL_T * 1.5, WALL_H * 1.04), pil))

    # Doors: one per wall, matching the GDD's room model.
    arched_door(parts, 0.0, hd + WALL_T * 0.5, "back", "N")
    arched_door(parts, -hw - WALL_T * 0.5, 0.0, "side", "W")
    arched_door(parts, hw + WALL_T * 0.5, 0.0, "side", "E")

    # Gilt vine scrollwork on the wall stretches either side of each door.
    gilt = mat("Gilt", GILT, shadow=0.30, light=0.34, grain=0.08)
    vine_scroll(parts, "VBL", (-ROOM_W * 0.28, hd + WALL_T * 0.02,
                               WALL_H * 0.60),
                ROOM_W * 0.30, WALL_H * 0.46, gilt, "back")
    vine_scroll(parts, "VBR", (ROOM_W * 0.28, hd + WALL_T * 0.02,
                               WALL_H * 0.60),
                ROOM_W * 0.30, WALL_H * 0.46, gilt, "back", flip=True)
    for side, x in (("L", -1), ("R", 1)):
        for j, cy in ((0, -ROOM_D * 0.28), (1, ROOM_D * 0.28)):
            vine_scroll(parts, f"VS{side}{j}",
                        (x * (hw + WALL_T * 0.02), cy, WALL_H * 0.60),
                        ROOM_D * 0.26, WALL_H * 0.46, gilt, "side",
                        flip=(j == 1))

    # A gilt string course running the length of each wall, tying the
    # scrollwork together instead of leaving it floating.
    for tag, loc, size in (
            ("CourseB", (0.0, hd + WALL_T * 0.02, WALL_H * 0.88),
             (ROOM_W + WALL_T, 0.10, 0.13)),
            ("CourseL", (-hw - WALL_T * 0.02, 0.0, WALL_H * 0.88),
             (0.10, ROOM_D, 0.13)),
            ("CourseR", (hw + WALL_T * 0.02, 0.0, WALL_H * 0.88),
             (0.10, ROOM_D, 0.13))):
        parts.append(rig.add_box(tag, loc, size, gilt))


# --------------------------------------------------------------------------
# Dressing: candles, ink, paper
# --------------------------------------------------------------------------

def build_dressing(parts):
    wax = mat("Wax", PARCHMENT, shadow=0.26, light=0.28, grain=0.10)
    sconce = mat("Sconce", GILT, shadow=0.30, light=0.32, grain=0.08)
    flame = flat("Flame", EMBER, strength=3.4)
    flame_core = flat("FlameCore", "FFC93C", strength=3.0)
    ink = mat("Ink", INK_BLACK, shadow=0.0, light=0.16, bands=3,
          grain=0.06, warm=INK_VIOLET)
    paper = mat("Paper", PARCHMENT, shadow=0.30, light=0.24, grain=0.12,
                grain_scale=26.0)
    quill = mat("Quill", PARCHMENT, shadow=0.34, light=0.20)

    hw, hd = ROOM_W * 0.5, ROOM_D * 0.5

    # ---- wall candles in gilt sconces ---------------------------------
    # On the wall caps and brackets, where they light the room from its
    # edges and never block the floor. Each one gets a point light below.
    for tag, (cx, cy) in CANDLE_SPOTS.items():
        parts.append(rig.add_cone(f"Sconce{tag}", (cx, cy, WALL_H + 0.12),
                                  radius1=0.34, radius2=0.20, depth=0.22,
                                  material=sconce, verts=8))
        parts.append(rig.add_cylinder(f"Candle{tag}", (cx, cy, WALL_H + 0.68),
                                      radius=0.22, depth=0.95, material=wax,
                                      verts=10))
        # Wax running down the side - the detail that makes a candle look
        # like it has been burning rather than like a white cylinder.
        for i, (ox, oy, length) in enumerate(((0.19, 0.03, 0.46),
                                              (-0.14, -0.12, 0.30),
                                              (0.04, 0.20, 0.22))):
            parts.append(rig.add_cylinder(
                f"Wax{tag}{i}", (cx + ox, cy + oy,
                                 WALL_H + 1.05 - length * 0.5),
                radius=0.055, depth=length, material=wax, verts=6))
        parts.append(rig.add_cone(f"Flame{tag}", (cx, cy, WALL_H + 1.34),
                                  radius1=0.17, radius2=0.0, depth=0.52,
                                  material=flame, verts=8))
        parts.append(rig.add_cone(f"FlameCore{tag}", (cx, cy, WALL_H + 1.26),
                                  radius1=0.09, radius2=0.0, depth=0.30,
                                  material=flame_core, verts=6))

    # ---- floor candelabra ---------------------------------------------
    for i, (cx, cy) in enumerate(FLOOR_LIGHTS):
        parts.append(rig.add_cylinder(f"StandBase{i}", (cx, cy, 0.10),
                                      radius=0.52, depth=0.20,
                                      material=sconce, verts=8))
        parts.append(rig.add_cylinder(f"StandShaft{i}", (cx, cy, 0.95),
                                      radius=0.13, depth=1.60,
                                      material=sconce, verts=8))
        parts.append(rig.add_cone(f"StandBowl{i}", (cx, cy, 1.86),
                                  radius1=0.22, radius2=0.46, depth=0.30,
                                  material=sconce, verts=8))
        parts.append(rig.add_cone(f"StandFlame{i}", (cx, cy, 2.34),
                                  radius1=0.30, radius2=0.0, depth=0.72,
                                  material=flame, verts=8))
        parts.append(rig.add_cone(f"StandCore{i}", (cx, cy, 2.22),
                                  radius1=0.16, radius2=0.0, depth=0.42,
                                  material=flame_core, verts=6))

    # ---- ink pools ----------------------------------------------------
    # Irregular, not ellipses. Each pool is a cluster of overlapping discs
    # at varying scales, so its edge is lumpy the way spilled ink is. These
    # are the boss's spoor - the Ink Scribe dissolves into exactly this - so
    # the environment carries the story from room 1.
    pools = [(-11.0, 5.4, 2.0), (12.6, -5.2, 1.7), (2.6, -8.4, 1.35),
             (-4.2, 8.6, 1.15), (8.0, 7.2, 0.95)]
    for p_i, (px, py, scale) in enumerate(pools):
        for b_i, (ox, oy, r) in enumerate(((0.0, 0.0, 1.0),
                                           (0.62, 0.30, 0.62),
                                           (-0.55, 0.22, 0.55),
                                           (0.18, -0.58, 0.48),
                                           (-0.30, -0.45, 0.40))):
            blob = rig.add_cylinder(
                f"Ink{p_i}_{b_i}",
                (px + ox * scale, py + oy * scale * 0.7, 0.02),
                radius=r * scale, depth=0.04, material=ink, verts=11,
                rotation=(0.0, 0.0, math.radians(37.0 * b_i)))
            blob.scale = (1.0, 0.70, 1.0)
            parts.append(blob)
        # A few flung droplets around the main spill.
        for d_i, (ox, oy, r) in enumerate(((1.5, 0.7, 0.16),
                                           (-1.4, -0.6, 0.12),
                                           (0.3, 1.5, 0.10))):
            drop = rig.add_cylinder(
                f"Drop{p_i}_{d_i}",
                (px + ox * scale, py + oy * scale * 0.7, 0.02),
                radius=r * scale, depth=0.04, material=ink, verts=7)
            drop.scale = (1.0, 0.70, 1.0)
            parts.append(drop)

    # ---- loose pages and dropped quills --------------------------------
    pages = [(-13.4, -2.4, 18), (-12.2, -3.8, -40), (8.4, 6.2, 25),
             (9.8, 6.9, -15), (-5.6, -8.2, 55), (15.2, 2.4, -62),
             (4.4, 8.4, 8), (-9.0, -6.0, 71), (13.0, 5.0, -28),
             (-1.2, 9.4, 44)]
    for i, (x, y, deg) in enumerate(pages):
        parts.append(rig.add_box(f"Page{i}", (x, y, 0.03), (1.0, 1.3, 0.03),
                                 paper, rotation=(0.0, 0.0,
                                                  math.radians(deg))))
    # Quills: a shaft and a vane, lying flat.
    for i, (x, y, deg) in enumerate(((-7.2, -4.4, 24), (10.4, 3.2, -52),
                                     (0.6, 7.8, 112))):
        r = (0.0, math.radians(90.0), math.radians(deg))
        parts.append(rig.add_cylinder(f"QuillShaft{i}", (x, y, 0.05),
                                      radius=0.05, depth=1.5,
                                      material=quill, verts=6, rotation=r))
        parts.append(rig.add_box(f"QuillVane{i}", (x + 0.3, y + 0.2, 0.05),
                                 (0.52, 0.22, 0.04), quill,
                                 rotation=(0.0, 0.0, math.radians(deg))))


# --------------------------------------------------------------------------
# Camera and light
# --------------------------------------------------------------------------

def setup_room_render():
    scene = bpy.context.scene
    engines = scene.render.bl_rna.properties["engine"].enum_items.keys()
    for cand in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        if cand in engines:
            scene.render.engine = cand
            break
    scene.render.resolution_x = RENDER_W
    scene.render.resolution_y = RENDER_H
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "Standard"
    scene.render.filter_size = 1.2
    for attr in ("use_raytracing", "use_bloom", "use_gtao"):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, False)

    # World colour: the dark beyond the walls.
    world = bpy.data.worlds.new("RoomWorld")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = \
        rig.hex_to_rgba(INK_BLACK)
    world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    scene.world = world

    # Ink outlines, lighter than on characters: a room drawn with character
    # weight lines turns into a colouring book.
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 0.85
    vl = scene.view_layers[0]
    vl.use_freestyle = True
    fs = vl.freestyle_settings
    if not fs.linesets:
        fs.linesets.new("Ink")
    ls = fs.linesets[0]
    ls.select_silhouette = True
    ls.select_border = True
    ls.select_crease = True
    ls.select_material_boundary = True
    ls.linestyle.color = rig.hex_to_rgba(INK_BLACK)[:3]
    ls.linestyle.thickness = 0.85

    # Camera
    cam_data = bpy.data.cameras.new("RoomCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = ROOM_W + 7.0
    cam = bpy.data.objects.new("RoomCam", cam_data)
    bpy.context.collection.objects.link(cam)
    elev = math.radians(ROOM_ELEVATION_DEG)
    dist = 60.0
    cam.location = (0.0, -dist * math.cos(elev) + 1.5,
                    dist * math.sin(elev) + 1.5)
    cam.rotation_euler = (math.radians(90.0) - elev, 0.0, 0.0)
    scene.camera = cam

    # Key light from the top-left, as everywhere else in the project.
    # Deliberately COOL and not very strong: in the reference the ambient
    # light is cold and the warmth comes only from flames. Make the key warm
    # as well and the whole contrast the picture is built on disappears.
    key = bpy.data.lights.new("Key", type="SUN")
    # Deliberately dim. The shader bands luminance over 0..1, so ambient
    # light sets the FLOOR of that range - and with the key at 1.05 plus a
    # fill and a bounce, the whole room sat around 0.8 and every candle pool
    # had only the top fifth of the ramp to work in. That is why a room full
    # of lit candles rendered perfectly flat. Keeping ambient near 0.1 gives
    # the pools somewhere to rise from.
    key.energy = 0.35
    key.color = (0.72, 0.74, 0.92)
    ko = bpy.data.objects.new("Key", key)
    bpy.context.collection.objects.link(ko)
    ko.rotation_euler = (math.radians(46.0), math.radians(-30.0),
                         math.radians(22.0))

    # Cool fill so shadows land in the violet end of the palette rather than
    # going flat black.
    fill = bpy.data.lights.new("Fill", type="SUN")
    fill.energy = 0.16
    fill.color = (0.44, 0.42, 0.64)
    fo = bpy.data.objects.new("Fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(66.0), math.radians(34.0),
                         math.radians(-120.0))

    # The light shaft. A wide spot aimed down across the room from the upper
    # left, which paints a bright warm patch on the floor.
    #
    # Done with light rather than geometry on purpose: a translucent shaft
    # object would be outlined by Freestyle like everything else, and an ink
    # line around a beam of light looks like a mistake.
    shaft = bpy.data.lights.new("Shaft", type="SPOT")
    # ~7000 W at 13 m lands near 1.0 in the shaft's centre.
    shaft.energy = 7200.0
    shaft.color = rig.hex_to_rgba("FFD9A8")[:3]
    shaft.spot_size = math.radians(86.0)
    shaft.spot_blend = 0.95
    shaft.shadow_soft_size = 1.4
    so = bpy.data.objects.new("Shaft", shaft)
    bpy.context.collection.objects.link(so)
    so.location = (-ROOM_W * 0.36, ROOM_D * 0.30, 13.0)
    so.rotation_euler = (math.radians(26.0), math.radians(-16.0), 0.0)

    # Candle point lights. Warm light on cool stone is the single thing that
    # makes the reference feel lit rather than flat, so these carry most of
    # the picture's colour contrast.
    for tag, (cx, cy) in CANDLE_SPOTS.items():
        pl = bpy.data.lights.new(f"Candle{tag}", type="POINT")
        pl.energy = 620.0
        pl.color = rig.hex_to_rgba(EMBER)[:3]
        pl.shadow_soft_size = 1.6
        po = bpy.data.objects.new(f"Candle{tag}", pl)
        bpy.context.collection.objects.link(po)
        # ABOVE the flame tip, not inside it. The flame cone spans
        # WALL_H+1.08 to WALL_H+1.60, and a point light placed inside opaque
        # geometry is blocked by that geometry - which is why four lit
        # candles were casting no light at all on the floor.
        po.location = (cx, cy, WALL_H + 1.95)

    # Warm pools around the room's edge, from the floor candelabra.
    for i, (cx, cy) in enumerate(FLOOR_LIGHTS):
        fl = bpy.data.lights.new(f"Floor{i}", type="POINT")
        # Energy is solved, not guessed. Irradiance = energy / (4*pi*d^2),
        # and the shader bands luminance over 0..1, so anything that puts
        # more than ~pi W/m^2 on the floor clips to the top band and the
        # pool stops being a pool. For a candelabra 2.1 m above the floor
        # that wants ~520 W: saturated at its foot, about 0.3 at 7 m out.
        # The previous 9000 W lit the entire 36 m room to the top band,
        # which is exactly why it looked flat.
        fl.energy = 520.0
        fl.color = rig.hex_to_rgba(EMBER)[:3]
        fl.shadow_soft_size = 2.2
        fo2 = bpy.data.objects.new(f"Floor{i}", fl)
        bpy.context.collection.objects.link(fo2)
        # Clear of the flame cone, which reaches z 2.70. See the note on the
        # wall sconces: a light inside its own flame mesh lights nothing.
        fo2.location = (cx, cy, 2.95)

    # A low warm bounce just above the floor, standing in for light kicking
    # back off the flagstones. Without it the floor's lower half goes dead.
    bounce = bpy.data.lights.new("Bounce", type="POINT")
    bounce.energy = 180.0
    bounce.color = rig.hex_to_rgba(CANDLE_WARM)[:3]
    bounce.shadow_soft_size = 6.0
    bo = bpy.data.objects.new("Bounce", bounce)
    bpy.context.collection.objects.link(bo)
    bo.location = (-ROOM_W * 0.18, ROOM_D * 0.05, 2.4)


def main():
    rig.clear_scene()
    setup_room_render()

    parts = []
    build_floor(parts)
    build_walls(parts)
    build_dressing(parts)

    # Emissive objects are light SOURCES; they must not also block light.
    for ob in parts:
        if any(k in ob.name for k in ("Flame", "Core", "Wax", "Candle")):
            ob.visible_shadow = False

    out_dir = os.path.join(rig.repo_root(), "assets", "sprites", "rooms")
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, "room_01.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("[room] ->", path)

    export_layout(os.path.join(out_dir, "room_01.json"))


def to_pixels(world_xyz):
    """
    Project a world point to pixel coordinates in the rendered image.

    Needed because the room is now a painted background rather than a grid of
    tiles, so Godot has no idea where the floor is. Guessing the floor's
    outline by eye would drift every time the camera or room size changed;
    projecting the real corners through the real camera cannot drift.

    Note the Y flip: Blender's normalised view has +Y up, Godot's screen
    space has +Y down.
    """
    from bpy_extras.object_utils import world_to_camera_view
    scene = bpy.context.scene
    co = world_to_camera_view(scene, scene.camera, Vector(world_xyz))
    return [round(co.x * RENDER_W, 1), round((1.0 - co.y) * RENDER_H, 1)]


def clamp_to_canvas(pt):
    """
    Keep a projected point inside the image.

    The floor's near edge runs slightly past the bottom of the frame, which
    is correct rather than a mistake: the camera looks INTO the room from
    that side, so there is no near wall and the floor simply continues off
    the bottom - exactly how the painted reference is composed. Clamping
    keeps the collision polygon inside the image it belongs to.
    """
    return [min(max(pt[0], 0.0), float(RENDER_W)),
            min(max(pt[1], 0.0), float(RENDER_H))]


def export_layout(path):
    """
    Write the room's collision and anchor points, in pixels, beside the PNG.

    pipeline/make_scenes.py reads this to build Room.tscn, so the engine and
    the art can never disagree about where a wall is.
    """
    hw, hd = ROOM_W * 0.5, ROOM_D * 0.5

    # Floor outline, anticlockwise on screen. The player is kept inside this.
    floor = [clamp_to_canvas(to_pixels((-hw, -hd, 0.0))),
             clamp_to_canvas(to_pixels((hw, -hd, 0.0))),
             clamp_to_canvas(to_pixels((hw, hd, 0.0))),
             clamp_to_canvas(to_pixels((-hw, hd, 0.0)))]

    doors = {
        "north": to_pixels((0.0, hd, 0.0)),
        "west": to_pixels((-hw, 0.0, 0.0)),
        "east": to_pixels((hw, 0.0, 0.0)),
    }

    # Enemy spawn points, spread so that wherever the player stands at least
    # one is the GDD's "at least 200 px from the player" away.
    spawn_cells = [(-0.62, 0.58), (0.0, 0.66), (0.62, 0.58),
                   (-0.70, -0.10), (0.70, -0.10), (0.0, -0.55)]
    spawns = [to_pixels((u * hw, v * hd, 0.0)) for u, v in spawn_cells]

    # Where the 1-3 interactive objects may appear. GDD: "objects placed on
    # 3-6 spawn markers per layout".
    object_cells = [(-0.40, 0.22), (0.40, 0.22), (0.0, -0.05),
                    (-0.46, -0.38), (0.46, -0.38)]
    objects = [to_pixels((u * hw, v * hd, 0.0)) for u, v in object_cells]

    data = {
        "name": "room_01",
        "image": "room_01.png",
        "size": [RENDER_W, RENDER_H],
        "floor_polygon": floor,
        "doors": doors,
        "spawn_markers": spawns,
        "object_markers": objects,
        "notes": ("Pixel coordinates in the rendered image. floor_polygon is "
                  "the walkable boundary; the south edge has no painted wall "
                  "because the camera looks in from that side, so its "
                  "collision is invisible by design."),
    }
    with open(path, "w") as fh:
        json.dump(data, fh, indent=2)
    print("[room] layout ->", path)

    _update_manifest(os.path.dirname(path), data)


def _update_manifest(out_dir, data):
    """
    Maintain layouts.json - the shared framing plus the list of rooms.

    The point of a SHARED framing block: if every room image puts its floor
    in the same rectangle of the same canvas, then every room uses the same
    collision polygon and the same door anchors. A new layout - including one
    painted or generated by hand rather than rendered here - costs a PNG and
    one line in this file, with no per-room collision authoring at all.

    docs/ROOM_BRIEF.md is the spec that art has to hit for that to hold.
    """
    path = os.path.join(out_dir, "layouts.json")
    manifest = {"framing": {}, "rooms": []}
    if os.path.exists(path):
        try:
            with open(path) as fh:
                manifest = json.load(fh)
        except ValueError:
            pass

    manifest["framing"] = {
        "canvas": data["size"],
        "floor_polygon": data["floor_polygon"],
        "doors": data["doors"],
        "spawn_markers": data["spawn_markers"],
        "object_markers": data["object_markers"],
        "spec": "docs/ROOM_BRIEF.md",
    }
    rooms = [r for r in manifest.get("rooms", []) if r.get("name") !=
             data["name"]]
    rooms.append({"name": data["name"], "image": data["image"],
                  "source": "blender"})
    manifest["rooms"] = sorted(rooms, key=lambda r: r["name"])

    with open(path, "w") as fh:
        json.dump(manifest, fh, indent=2)
    print("[room] manifest ->", path, "(%d rooms)" % len(manifest["rooms"]))


if __name__ == "__main__":
    main()
