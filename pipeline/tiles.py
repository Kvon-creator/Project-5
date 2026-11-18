"""
Floor and wall tiles.

GDD, Art direction: "Floors and walls are painted 2D tiles from the same
angle."

One deliberate departure, explained because it matters to anyone editing this:

FLOOR tiles are rendered from STRAIGHT DOWN, not from the 3/4 rig. A floor
quad seen at 45 degrees is foreshortened to 71% in one axis, so its texture
can no longer tile against its neighbour without visible seams, and a square
room would need rhombus-shaped tiles. Every top-down game that renders props
at 3/4 does this - the floor is drawn flat and the props stand on it. Walls
DO use the 3/4 rig, because a wall is a vertical object like a character and
has to share their light direction.

The avoid list is the other constraint here:
    Busy, high-contrast floor textures where bullets travel
so the floor is close to flat Crypt Stone with only faint seams and a slight
value drift. It must never compete with a bullet.

Run:
    blender -b --python pipeline/tiles.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

PX_PER_M = 128 / 3.90

# A 64 px tile at ~32.8 px/m is just under 2 m square. Round numbers in pixels
# matter more than round numbers in metres for a tilemap, so 64 px wins.
TILE_PX = 64
TILE_M = TILE_PX / PX_PER_M


def _top_down_camera(size_m: float) -> None:
    """Replace the 3/4 camera with one looking straight down."""
    for ob in list(bpy.data.objects):
        if ob.type == "CAMERA":
            bpy.data.objects.remove(ob, do_unlink=True)

    cam_data = bpy.data.cameras.new("FloorCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size_m
    cam = bpy.data.objects.new("FloorCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 10.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)   # straight down
    bpy.context.scene.camera = cam


def build_floor(variant: int):
    """
    A Crypt Stone flagstone.

    `variant` picks a different seam layout so a room laid with 3-4 variants
    does not show an obvious repeat. Values stay within a few percent of each
    other - the point is to break the grid, not to decorate the floor.
    """
    base = rig.cel_material(f"Floor{variant}", "2B2335",
                            shadow_mix=0.20, highlight_mix=0.10, bands=2)
    seam = rig.cel_material(f"FloorSeam{variant}", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.12, bands=2)
    chip = rig.cel_material(f"FloorChip{variant}", "2B2335",
                            shadow_mix=0.0, highlight_mix=0.14, bands=2)

    parts = []
    half = TILE_M * 0.5
    # The slab itself, filling the frame exactly so tiles butt up seamlessly.
    parts.append(rig.add_box("Slab", (0.0, 0.0, 0.0),
                             (TILE_M, TILE_M, 0.20), base))

    # Seams along two edges only. Tiling the map then produces a continuous
    # grid without doubling the line weight where two tiles meet.
    seam_w = TILE_M * 0.035
    parts.append(rig.add_box("SeamN", (0.0, half - seam_w * 0.5, 0.102),
                             (TILE_M, seam_w, 0.02), seam))
    parts.append(rig.add_box("SeamE", (half - seam_w * 0.5, 0.0, 0.102),
                             (seam_w, TILE_M, 0.02), seam))

    # One or two faint chips, offset per variant. Low contrast on purpose.
    spots = [
        [(-0.18, 0.12, 0.16)],
        [(0.22, -0.20, 0.13), (-0.26, -0.08, 0.09)],
        [(0.05, 0.26, 0.11)],
        [],
    ][variant % 4]
    for i, (x, y, r) in enumerate(spots):
        parts.append(rig.add_cylinder(f"Chip{i}",
                                      (x * TILE_M, y * TILE_M, 0.103),
                                      radius=r * TILE_M * 0.5, depth=0.02,
                                      material=chip, verts=6))
    return parts


def build_wall():
    """
    A Stone Light wall block, rendered through the 3/4 rig so its lighting
    matches the characters standing in front of it.

    Rendered one tile wide and tall enough to show a face plus a cap, which
    is what a top-down room needs: the player sees the top of the wall and a
    sliver of its front.
    """
    stone = rig.cel_material("WallStone", "4E4458",
                             shadow_mix=0.42, highlight_mix=0.24)
    cap = rig.cel_material("WallCap", "4E4458",
                           shadow_mix=0.25, highlight_mix=0.34)
    dark = rig.cel_material("WallDark", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.16)

    parts = []
    # Wall height is capped by the frame, not by taste.
    #
    # A block of width w and height h seen at 45 deg paints a vertical extent
    # of about (w + h) * cos(45) = 0.707 * (w + h). The wall has to fit a
    # 64 px frame that covers TILE_M metres, and its width is already TILE_M,
    # so:  0.707 * (TILE_M + h) <= TILE_M  ->  h <= 0.41 * TILE_M.
    #
    # 0.37 * TILE_M leaves a little headroom for the ink outline. Going
    # taller makes the wall ONE TILE WIDE BUT TWO TILES TALL in the atlas,
    # which needs a multi-cell tile declaration and makes every wall occupy
    # two map cells - much more complexity than a chunky wall is worth.
    h = TILE_M * 0.37
    parts.append(rig.add_box("Block", (0.0, 0.0, h * 0.5),
                             (TILE_M, TILE_M, h), stone))
    # A lighter cap so the top surface separates from the front face.
    parts.append(rig.add_box("Cap", (0.0, 0.0, h + 0.015),
                             (TILE_M, TILE_M, 0.03), cap))
    # A recessed course line across the front, for scale.
    parts.append(rig.add_box("Course", (0.0, -TILE_M * 0.5 + 0.02, h * 0.42),
                             (TILE_M * 0.98, 0.04, 0.05), dark))
    return parts


def build_door(open_state: bool):
    """
    GDD, Room-Based Combat: "Doors - Lock on entry; unlock when the last wave
    is defeated."

    Two states. Locked is the one that matters: the player needs to see at a
    glance that the room is still holding them, so the locked door carries a
    Blood Rust bar across it. Unlocked is an open dark arch - the way out,
    reading as a hole rather than as an object.
    """
    frame_mat = rig.cel_material(f"DoorFrame{open_state}", "4E4458",
                                 shadow_mix=0.42, highlight_mix=0.26)
    void = rig.cel_material(f"DoorVoid{open_state}", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.10)
    bar = rig.cel_material(f"DoorBar{open_state}", "8E2A2A",
                           shadow_mix=0.30, highlight_mix=0.30)

    parts = []
    h = TILE_M * 1.15
    w = TILE_M * 1.20
    # Jambs either side.
    for side, x in (("L", -1), ("R", 1)):
        parts.append(rig.add_box(f"Jamb{side}", (x * w * 0.5, 0.0, h * 0.5),
                                 (TILE_M * 0.30, TILE_M * 0.9, h),
                                 frame_mat))
    # Lintel across the top.
    parts.append(rig.add_box("Lintel", (0.0, 0.0, h + TILE_M * 0.12),
                             (w + TILE_M * 0.30, TILE_M * 0.9,
                              TILE_M * 0.24), frame_mat))
    # The opening.
    parts.append(rig.add_box("Void", (0.0, 0.10, h * 0.48),
                             (w * 0.78, TILE_M * 0.6, h * 0.92), void))

    if not open_state:
        # Locked: two Blood Rust bars.
        for i, z in enumerate((h * 0.34, h * 0.66)):
            parts.append(rig.add_box(f"Bar{i}", (0.0, -TILE_M * 0.22, z),
                                     (w * 0.84, TILE_M * 0.12,
                                      TILE_M * 0.13), bar))
    return parts


def _render(name, builder, frame_px, frame_height_m, top_down=False,
            line_px=1.4, yaw_deg=0.0):
    rig.clear_scene()
    rig.setup_render(frame_px=frame_px, subject_height_m=1.0,
                     frame_height_m=frame_height_m)
    bpy.context.scene.render.line_thickness = line_px

    parts = builder()
    pivot = rig.group_under_pivot(parts, f"{name}Pivot")
    pivot.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))

    if top_down:
        _top_down_camera(frame_height_m)

    rig.render_single(rig.sprite_dir("tiles"), name)


def main():
    # Floors: straight down, frame exactly one tile, so they tile seamlessly.
    for v in range(4):
        _render(f"floor_{v}", lambda vv=v: build_floor(vv),
                TILE_PX, TILE_M, top_down=True,
                # Almost no ink on the floor. A bold outline on every tile
                # would turn the floor into the grid the avoid list warns
                # about, and bullets have to win against it.
                line_px=0.8)

    # Wall: exactly ONE tile, 64 px covering TILE_M metres, so it drops into
    # the tilemap as a single cell. build_wall() keeps the block short enough
    # to fit this frame - see the height note there.
    _render("wall", build_wall, TILE_PX, TILE_M, line_px=1.2)
    _render("door_locked", lambda: build_door(False),
            TILE_PX * 3, TILE_M * 3.0, line_px=1.4)
    _render("door_open", lambda: build_door(True),
            TILE_PX * 3, TILE_M * 3.0, line_px=1.4)

    print("[tiles] done ->", rig.sprite_dir("tiles"))


if __name__ == "__main__":
    main()
