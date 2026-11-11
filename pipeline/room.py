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
CANDLE_WARM = "BE9E91"    # warm lit stone
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


def mat(name, hex_colour, shadow=0.45, light=0.22, bands=5, emit=1.0):
    return rig.cel_material(name, hex_colour, shadow_mix=shadow,
                            highlight_mix=light, bands=bands,
                            emission_strength=emit)


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
    stone = mat("FloorStone", STONE_LIT, shadow=0.40, light=0.10, bands=3)
    seam = mat("FloorSeam", STONE_SHADOW, shadow=0.30, light=0.10, bands=2)
    inlay = mat("FloorInlay", STONE_SHADOW, shadow=0.20, light=0.18, bands=2)

    parts.append(rig.add_box("Floor", (0, 0, -0.1), (ROOM_W, ROOM_D, 0.2),
                             stone))

    # Flagstone seams every 4 m. Thin, dark, barely there.
    step = 7.0
    x = -ROOM_W * 0.5 + step
    while x < ROOM_W * 0.5 - 0.1:
        parts.append(rig.add_box(f"SeamV{int(x)}", (x, 0, 0.005),
                                 (0.06, ROOM_D, 0.01), seam))
        x += step
    y = -ROOM_D * 0.5 + step
    while y < ROOM_D * 0.5 - 0.1:
        parts.append(rig.add_box(f"SeamH{int(y)}", (0, y, 0.005),
                                 (ROOM_W, 0.06, 0.01), seam))
        y += step

    # Rune inlay: concentric rings at the room's centre, like the arena
    # reference. Real annuli - the first pass drew a ring and then a filled
    # disc of floor stone on top of it, which buried every inner ring and
    # left one flat circle.
    for radius, width in ((7.2, 0.16), (6.6, 0.09), (3.4, 0.12), (1.3, 0.1)):
        parts.append(rig.add_ring(f"Ring{int(radius * 10)}", (0, 0, 0.01),
                                  radius=radius, thickness=width,
                                  height=0.02, material=inlay, verts=56))

    # Eight spokes, so the inlay reads as a sigil rather than as targets.
    for i in range(8):
        a = math.tau * i / 8.0
        parts.append(rig.add_box(f"Spoke{i}",
                                 (math.cos(a) * 5.0, math.sin(a) * 5.0, 0.01),
                                 (2.6, 0.12, 0.016), inlay,
                                 rotation=(0, 0, a)))


# --------------------------------------------------------------------------
# Walls, pilasters, filigree, doors
# --------------------------------------------------------------------------

def filigree_panel(parts, cx, cy, width, facing, tag):
    """
    A band of gilt vine work on a wall face.

    Real illuminated-manuscript vine scrollwork is not something low-poly
    geometry can imitate convincingly, so this does not try. It lays down a
    rhythm of small gilt diamonds and connecting stems - enough to read as
    "ornate band" at room scale and to catch the ink outline, and a clear
    placeholder for painted-over detail later.
    """
    gilt = mat("Gilt" + tag, GILT, shadow=0.35, light=0.30)
    n = max(3, int(width / 1.6))
    for i in range(n):
        t = (i + 0.5) / n - 0.5
        if facing == "back":
            x, y = cx + t * width, cy
            rot = (0.0, 0.0, 0.0)
            stem = (width / n * 0.55, 0.12, 0.10)
            dia = (0.42, 0.14, 0.42)
        else:
            x, y = cx, cy + t * width
            rot = (0.0, 0.0, math.radians(90.0))
            stem = (0.12, width / n * 0.55, 0.10)
            dia = (0.14, 0.42, 0.42)
        z = WALL_H * 0.60
        parts.append(rig.add_box(f"Stem{tag}{i}", (x, y, z), stem, gilt))
        parts.append(rig.add_box(f"Leaf{tag}{i}", (x, y, z + 0.42), dia, gilt,
                                 rotation=(0, math.radians(45), rot[2])))


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


def build_walls(parts):
    stone = mat("WallStone", STONE_MID, shadow=0.45, light=0.26)
    cap = mat("WallCap", STONE_SHADOW, shadow=0.30, light=0.22)
    pil = mat("Pilaster", CANDLE_WARM, shadow=0.45, light=0.24)

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

    # Filigree bands on the wall stretches either side of each door.
    filigree_panel(parts, -ROOM_W * 0.27, hd + WALL_T * 0.35,
                   ROOM_W * 0.34, "back", "BL")
    filigree_panel(parts, ROOM_W * 0.27, hd + WALL_T * 0.35,
                   ROOM_W * 0.34, "back", "BR")
    for side, x in (("L", -1), ("R", 1)):
        for j, cy in ((0, -ROOM_D * 0.3), (1, ROOM_D * 0.3)):
            filigree_panel(parts, x * (hw + WALL_T * 0.1), cy,
                           ROOM_D * 0.3, "side", f"S{side}{j}")


# --------------------------------------------------------------------------
# Dressing: candles, ink, paper
# --------------------------------------------------------------------------

def build_dressing(parts):
    wax = mat("Wax", PARCHMENT, shadow=0.30, light=0.30)
    flame = rig.flat_material("Flame", EMBER, strength=3.0)
    ink = mat("Ink", INK_BLACK, shadow=0.0, light=0.06, bands=2)
    paper = mat("Paper", PARCHMENT, shadow=0.35, light=0.25, bands=2)

    hw, hd = ROOM_W * 0.5, ROOM_D * 0.5

    # Candles standing on the wall caps, which is where the reference puts
    # them - they light the room from its edges and never block the floor.
    for tag, (cx, cy) in (("A", (-hw + 2.0, hd - 0.2)),
                          ("B", (hw - 2.0, hd - 0.2)),
                          ("C", (-hw + 0.2, -hd * 0.3))):
        parts.append(rig.add_cylinder(f"Candle{tag}", (cx, cy, WALL_H + 0.9),
                                      radius=0.34, depth=1.3, material=wax,
                                      verts=10))
        parts.append(rig.add_cone(f"Flame{tag}", (cx, cy, WALL_H + 1.85),
                                  radius1=0.20, radius2=0.0, depth=0.62,
                                  material=flame, verts=8))

    # Ink pools. Irregular overlapping discs, flat on the floor. These are
    # the boss's spoor - the Ink Scribe dissolves into exactly this - so the
    # environment carries the story even in room 1.
    pools = [(-11.5, 4.6, 1.5), (-10.2, 3.7, 0.95), (13.0, -4.4, 1.25),
             (14.0, -3.5, 0.8), (3.0, -7.2, 1.0), (-3.5, 7.4, 0.9)]
    for i, (x, y, r) in enumerate(pools):
        blob = rig.add_cylinder(f"Ink{i}", (x, y, 0.02), radius=r,
                                depth=0.04, material=ink, verts=12)
        blob.scale = (1.0, 0.72, 1.0)
        parts.append(blob)

    # Loose manuscript pages, scattered flat and at angles.
    pages = [(-13.0, -2.0, 18), (-12.0, -3.4, -40), (7.5, 5.6, 25),
             (9.0, 6.2, -15), (-5.0, -7.4, 55), (14.5, 2.0, -62),
             (4.0, 7.6, 8)]
    for i, (x, y, deg) in enumerate(pages):
        parts.append(rig.add_box(f"Page{i}", (x, y, 0.03), (1.0, 1.3, 0.04),
                                 paper, rotation=(0, 0, math.radians(deg))))


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
    scene.render.line_thickness = 1.1
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
    ls.linestyle.thickness = 1.1

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
    key = bpy.data.lights.new("Key", type="SUN")
    key.energy = 2.6
    key.color = (1.0, 0.93, 0.84)
    ko = bpy.data.objects.new("Key", key)
    bpy.context.collection.objects.link(ko)
    ko.rotation_euler = (math.radians(46.0), math.radians(-30.0),
                         math.radians(22.0))

    # Cool fill, so shadows land in the violet end of the palette rather
    # than going flat black.
    fill = bpy.data.lights.new("Fill", type="SUN")
    fill.energy = 0.55
    fill.color = (0.48, 0.44, 0.62)
    fo = bpy.data.objects.new("Fill", fill)
    bpy.context.collection.objects.link(fo)
    fo.rotation_euler = (math.radians(66.0), math.radians(34.0),
                         math.radians(-120.0))

    # Candle point lights. The warm-light-on-cool-stone contrast is the
    # single thing that makes the painted reference feel lit.
    hw, hd = ROOM_W * 0.5, ROOM_D * 0.5
    for i, (cx, cy) in enumerate(((-hw + 2.0, hd - 0.2), (hw - 2.0, hd - 0.2),
                                  (-hw + 0.2, -hd * 0.3))):
        pl = bpy.data.lights.new(f"Candle{i}", type="POINT")
        pl.energy = 900.0
        pl.color = rig.hex_to_rgba(EMBER)[:3]
        pl.shadow_soft_size = 1.2
        po = bpy.data.objects.new(f"Candle{i}", pl)
        bpy.context.collection.objects.link(po)
        po.location = (cx, cy, WALL_H + 1.9)


def main():
    rig.clear_scene()
    setup_room_render()

    parts = []
    build_floor(parts)
    build_walls(parts)
    build_dressing(parts)

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
