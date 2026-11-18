"""
Props: the three interactive objects, the power-up, and the bullets.

Reference: docs/reference/props-sheet.png, which maps one-to-one onto the
GDD's Environmental Combat table:

    Explosive Lamp Oil      the explosive barrel
                            2 hits to detonate, 30 damage within 96 px (3 m)
    Defensive Tome Stack    destructible cover, breaks after 5 hits
                            the sheet supplies three damage stages
    Scribe's Trap           15 damage when stepped on, re-arms after 2 s
                            its spikes are PEN NIBS
    Luminous Pigment Shell  the damage power-up dropped every 5th kill
                            teal, because teal is the player's colour

Everything renders through the same rig as the anchor asset at the same
pixels-per-metre, so a lamp oil flask standing next to the Nib Knight is the
right size without anyone eyeballing it.

Run:
    blender -b --python pipeline/props.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

# Pixels per metre, inherited from the anchor: the Nib Knight is 1.60 m in a
# 3.80 m frame at 128 px.
PX_PER_M = 128 / 3.80


def frame_m(frame_px):
    return frame_px / PX_PER_M


def prop_materials(tag):
    return {
        "rust": rig.cel_material(f"{tag}Rust", "BA7977",
                                 shadow_mix=0.30, highlight_mix=0.22),
        "leather": rig.cel_material(f"{tag}Leather", "70280C",
                                    shadow_mix=0.26, highlight_mix=0.28),
        "parchment": rig.cel_material(f"{tag}Parch", "E2C5A8",
                                      shadow_mix=0.28, highlight_mix=0.16),
        "steel": rig.cel_material(f"{tag}Steel", "868178",
                                  shadow_mix=0.26, highlight_mix=0.32),
        "ink": rig.cel_material(f"{tag}Ink", "18030A",
                                shadow_mix=0.0, highlight_mix=0.16),
        "plum": rig.cel_material(f"{tag}Plum", "421C39",
                                 shadow_mix=0.10, highlight_mix=0.28),
        "stone": rig.cel_material(f"{tag}Stone", "776B70",
                                  shadow_mix=0.30, highlight_mix=0.24),
        # Emissive. Fire and the pigment glow have to hold their colour at
        # every value, because they are what the player reads the object by.
        "fire": rig.flat_material(f"{tag}Fire", "F06A2A", strength=2.6),
        "fire_core": rig.flat_material(f"{tag}FireCore", "FFC93C",
                                       strength=2.2),
        "teal": rig.flat_material(f"{tag}Teal", "35D6C4", strength=2.4),
        "teal_soft": rig.flat_material(f"{tag}TealSoft", "98E5DD",
                                       strength=1.3),
    }


# --------------------------------------------------------------------------
# Explosive Lamp Oil - the barrel
# --------------------------------------------------------------------------

def build_lamp_oil():
    """
    A round glass flask of burning oil slung in a rope net, with a lit wick.

    The whole object is Ember and it is the only Ember thing on the floor, so
    "this one explodes" is legible at a glance while the player is dodging.
    The rope net is what stops it reading as a plain glowing ball - it gives
    the silhouette hard lines to catch the ink outline.
    """
    m = prop_materials("Lamp")
    parts = []

    # Glass body, glowing from the oil inside.
    parts.append(rig.add_sphere("Flask", (0.0, 0.0, 0.40), radius=0.30,
                                material=m["fire"], segments=14, rings=8))
    # A denser core, so the middle is brightest.
    parts.append(rig.add_sphere("Oil", (0.0, 0.0, 0.37), radius=0.20,
                                material=m["fire_core"], segments=10,
                                rings=6))

    # Rope net: two vertical hoops crossed over the flask plus a waist band.
    for i, yaw in enumerate((0.0, 90.0)):
        hoop = rig.add_ring(f"Net{i}", (0.0, 0.0, 0.40), radius=0.305,
                            thickness=0.045, height=0.045,
                            material=m["leather"], verts=20)
        hoop.rotation_euler = (math.radians(90.0), 0.0, math.radians(yaw))
        parts.append(hoop)
    parts.append(rig.add_ring("NetBand", (0.0, 0.0, 0.40), radius=0.305,
                              thickness=0.05, height=0.05,
                              material=m["leather"], verts=20))

    # Neck, cork and wick.
    parts.append(rig.add_cylinder("Neck", (0.0, 0.0, 0.73), radius=0.095,
                                  depth=0.18, material=m["steel"], verts=8))
    parts.append(rig.add_cylinder("Collar", (0.0, 0.0, 0.80), radius=0.12,
                                  depth=0.05, material=m["leather"],
                                  verts=8))
    parts.append(rig.add_cylinder("Wick", (0.0, 0.0, 0.86), radius=0.03,
                                  depth=0.09, material=m["ink"], verts=6))

    # Flame: a tapered cone with a brighter heart, plus a couple of embers
    # lifting off. Small and tight - the avoid list bans glow that could hide
    # a bullet, and this sits on the floor where bullets travel.
    parts.append(rig.add_cone("Flame", (0.0, 0.0, 1.02), radius1=0.09,
                              radius2=0.0, depth=0.26, material=m["fire"],
                              verts=8))
    parts.append(rig.add_cone("FlameCore", (0.0, 0.0, 0.98), radius1=0.05,
                              radius2=0.0, depth=0.15,
                              material=m["fire_core"], verts=6))
    for i, (x, z, r) in enumerate(((0.07, 1.22, 0.022),
                                   (-0.05, 1.33, 0.016))):
        parts.append(rig.add_sphere(f"Ember{i}", (x, 0.02, z), r,
                                    m["fire"], segments=6, rings=4))

    # A small foot ring so it sits rather than floats.
    parts.append(rig.add_ring("Foot", (0.0, 0.0, 0.05), radius=0.20,
                              thickness=0.055, height=0.07,
                              material=m["leather"], verts=14))
    return parts


# --------------------------------------------------------------------------
# Defensive Tome Stack - destructible cover
# --------------------------------------------------------------------------

def _book(parts, tag, m, loc, size, yaw=0.0, tilt=0.0, torn=False):
    """One leather-bound book: covers, page block, and a spine."""
    w, d, h = size
    x, y, z = loc
    rot = (math.radians(tilt), 0.0, math.radians(yaw))
    # The page block, slightly inset so parchment shows along the edges.
    parts.append(rig.add_box(f"{tag}Pages", (x, y, z),
                             (w * 0.94, d * 0.90, h * 0.72),
                             m["parchment"], rotation=rot))
    # Covers top and bottom.
    for i, dz in ((0, h * 0.5 - h * 0.09), (1, -h * 0.5 + h * 0.09)):
        parts.append(rig.add_box(f"{tag}Cover{i}", (x, y, z + dz),
                                 (w, d, h * 0.18), m["leather"],
                                 rotation=rot))
    # Spine down one side.
    sx = x - math.cos(math.radians(yaw)) * w * 0.5
    sy = y - math.sin(math.radians(yaw)) * w * 0.5
    parts.append(rig.add_box(f"{tag}Spine", (sx, sy, z),
                             (w * 0.10, d, h), m["leather"], rotation=rot))
    # Metal corner plates - the detail that makes it read as a bound tome
    # rather than a brick.
    for i, (ox, oy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        parts.append(rig.add_box(
            f"{tag}Corner{i}",
            (x + ox * w * 0.40, y + oy * d * 0.40, z + h * 0.44),
            (w * 0.18, d * 0.18, h * 0.22), m["steel"], rotation=rot))
    if torn:
        # Pages bursting out of the fore-edge.
        for i in range(3):
            parts.append(rig.add_box(
                f"{tag}Loose{i}",
                (x + w * 0.52 + i * 0.03, y - 0.04 + i * 0.07, z + h * 0.1),
                (0.30, 0.22, 0.02), m["parchment"],
                rotation=(math.radians(10.0 * i - 10),
                          math.radians(16.0), math.radians(yaw + 12 * i))))


def build_tomes(stage):
    """
    GDD: "Destructible cover - Blocks enemy bullets; breaks after 5 hits".

    Three stages, which the reference sheet already lays out:
        0  intact      strapped and padlocked, square and solid
        1  cracked     lock burst, books shoved out of line, pages spilling
        2  crumbling   collapsing, torn covers, pages all over the floor

    The player has to be able to read how close cover is to breaking, because
    the GDD lets them "trade cover for a Shockwave" - and you cannot make
    that trade without knowing how many hits are left.
    """
    m = prop_materials(f"Tome{stage}")
    parts = []

    # Book sizes, bottom to top. A stack narrows as it rises.
    books = [
        ((0.00, 0.00, 0.13), (1.15, 0.85, 0.26), 0.0),
        ((0.02, 0.01, 0.38), (1.08, 0.80, 0.24), -4.0),
        ((-0.02, -0.01, 0.60), (1.00, 0.74, 0.21), 3.0),
        ((0.01, 0.02, 0.79), (0.90, 0.68, 0.18), -6.0),
    ]
    if stage == 0:
        offsets = [(0, 0, 0)] * 4
        tilts = [0, 0, 0, 0]
    elif stage == 1:
        # Shoved out of line.
        offsets = [(0, 0, 0), (0.10, 0.04, 0), (-0.13, -0.05, 0),
                   (0.08, 0.02, -0.02)]
        tilts = [0, 3, -5, 8]
    else:
        # Collapsing: the top book has slid off and the stack is shorter.
        offsets = [(0, 0, 0), (0.16, 0.07, -0.02), (-0.22, -0.09, -0.05),
                   (0.40, 0.14, -0.30)]
        tilts = [2, -7, 11, 26]

    for i, ((loc, size, yaw), off, tilt) in enumerate(
            zip(books, offsets, tilts)):
        if stage == 2 and i == 3:
            size = (size[0] * 0.92, size[1] * 0.92, size[2])
        _book(parts, f"B{i}", m,
              (loc[0] + off[0], loc[1] + off[1], loc[2] + off[2]),
              size, yaw=yaw + (tilt * 0.6), tilt=tilt,
              torn=(stage >= 1 and i in (1, 2)))

    if stage == 0:
        # Strap and padlock holding the stack shut.
        parts.append(rig.add_box("Strap", (0.0, 0.0, 0.46),
                                 (0.18, 0.92, 0.94), m["leather"]))
        parts.append(rig.add_box("Lock", (0.0, -0.46, 0.46),
                                 (0.16, 0.10, 0.20), m["steel"]))
        parts.append(rig.add_ring("Shackle", (0.0, -0.46, 0.57),
                                  radius=0.07, thickness=0.03, height=0.03,
                                  material=m["steel"], verts=12))
    else:
        # Burst strap, hanging.
        parts.append(rig.add_box("StrapCut", (0.12, 0.30, 0.50),
                                 (0.16, 0.34, 0.60), m["leather"],
                                 rotation=(math.radians(22.0), 0.0, 0.0)))
        parts.append(rig.add_box("LockBroken", (0.30, -0.46, 0.05),
                                 (0.15, 0.10, 0.18), m["steel"],
                                 rotation=(0.0, math.radians(38.0), 0.0)))

    # Loose pages on the floor around the base, more as it breaks.
    scatter = {0: [], 1: [(-0.70, 0.30, 24), (0.72, -0.26, -38)],
               2: [(-0.80, 0.34, 18), (0.84, -0.30, -46), (0.30, 0.62, 62),
                   (-0.42, -0.58, -14), (0.95, 0.20, 33)]}[stage]
    for i, (x, y, deg) in enumerate(scatter):
        parts.append(rig.add_box(f"Fallen{i}", (x, y, 0.015),
                                 (0.36, 0.28, 0.02), m["parchment"],
                                 rotation=(0.0, 0.0, math.radians(deg))))
    return parts


# --------------------------------------------------------------------------
# Scribe's Trap
# --------------------------------------------------------------------------

def build_trap(state):
    """
    A rusted frame of upturned pen nibs.

    state: "disarmed" | "armed" | "triggered"

    The nibs are the joke and the theme in one object: the dungeon kills you
    with writing implements. Each spike is a flattened tapered blade with a
    slit, the same shape as the hero's spear head, just small and hostile.

    Three states because the 2 s re-arm window is something the player reads
    off the floor mid-fight - and Jarman's enemies "steer clear of active
    hazards within 75 px", so which traps are live decides where enemies will
    refuse to walk.
    """
    m = prop_materials(f"Trap{state}")
    parts = []
    size = 1.45
    half = size * 0.5

    # Base plate, sitting almost flush so it never hides a bullet.
    parts.append(rig.add_box("Plate", (0.0, 0.0, 0.035),
                             (size, size, 0.07), m["plum"]))
    # Rusted frame around the edge.
    for i, (ox, oy, w, d) in enumerate((
            (0, half, size + 0.12, 0.14), (0, -half, size + 0.12, 0.14),
            (half, 0, 0.14, size + 0.12), (-half, 0, 0.14, size + 0.12))):
        parts.append(rig.add_box(f"Frame{i}", (ox, oy, 0.09),
                                 (w, d, 0.16), m["rust"]))
    # Corner bolts.
    for i, (ox, oy) in enumerate(((1, 1), (1, -1), (-1, 1), (-1, -1))):
        parts.append(rig.add_cylinder(
            f"Bolt{i}", (ox * half, oy * half, 0.18), radius=0.06,
            depth=0.06, material=m["steel"], verts=6))

    # The nib grid. 4 x 4, inset from the frame.
    n = 4
    spacing = (size - 0.34) / (n - 1)
    ink_mat = m["plum"] if state == "triggered" else m["steel"]
    for ix in range(n):
        for iy in range(n):
            x = -((n - 1) * spacing * 0.5) + ix * spacing
            y = -((n - 1) * spacing * 0.5) + iy * spacing

            if state == "disarmed":
                # Retracted: only the sockets show, so the plate reads safe.
                parts.append(rig.add_cylinder(
                    f"Socket{ix}{iy}", (x, y, 0.075), radius=0.055,
                    depth=0.04, material=m["ink"], verts=6))
                continue

            height = 0.42
            nib = rig.add_cone(f"Nib{ix}{iy}", (x, y, 0.09 + height * 0.5),
                               radius1=0.075, radius2=0.008, depth=height,
                               material=ink_mat, verts=6)
            # Flattened into a blade, like a real nib - and like the hero's.
            nib.scale = (1.0, 0.42, 1.0)
            parts.append(nib)
            # The slit up the centre of each nib.
            parts.append(rig.add_box(f"Slit{ix}{iy}", (x, y, 0.16),
                                     (0.014, 0.02, 0.18), m["ink"]))

    if state == "triggered":
        # Violet ink running off the points, and a couple of flecks thrown
        # clear. This is what "it just fired" looks like from across a room.
        for ix in range(n):
            for iy in range(n):
                if (ix + iy) % 2:
                    continue
                x = -((n - 1) * spacing * 0.5) + ix * spacing
                y = -((n - 1) * spacing * 0.5) + iy * spacing
                parts.append(rig.add_sphere(f"Drop{ix}{iy}",
                                            (x, y, 0.56), 0.05,
                                            m["ink"], segments=6, rings=4))
        for i, (x, y, z, r) in enumerate(((0.52, 0.30, 0.74, 0.045),
                                          (-0.44, -0.26, 0.82, 0.035),
                                          (0.10, -0.50, 0.68, 0.030))):
            parts.append(rig.add_sphere(f"Fleck{i}", (x, y, z), r,
                                        m["plum"], segments=6, rings=4))
    return parts


# --------------------------------------------------------------------------
# Luminous Pigment Shell - the damage power-up
# --------------------------------------------------------------------------

def build_pigment_shell():
    """
    GDD, Combat Rewards: "Damage power-up drop - Every 5th enemy defeated",
    "+20% weapon damage for 10 s".

    A spiral shell full of glowing teal pigment, sitting in dark litter.
    Teal because Spirit Teal is the player's colour - the same teal as their
    shots and the nib - so a pickup never gets confused with a threat. And a
    shell, which quietly ties it back to the snail.
    """
    m = prop_materials("Shell")
    parts = []

    # Litter it sits in, so it does not look like it is floating.
    for i, (x, y, r, deg) in enumerate(((-0.22, 0.10, 0.20, 20),
                                        (0.24, -0.08, 0.17, -35),
                                        (0.05, 0.22, 0.15, 58))):
        leaf = rig.add_cylinder(f"Litter{i}", (x, y, 0.015), radius=r,
                                depth=0.03, material=m["ink"], verts=7,
                                rotation=(0.0, 0.0, math.radians(deg)))
        leaf.scale = (1.0, 0.55, 1.0)
        parts.append(leaf)

    # Shell: whorls of decreasing radius spiralling up, like the snail's but
    # tipped onto its side.
    for i, (r, t, dz, dy) in enumerate(((0.26, 0.14, 0.14, 0.00),
                                        (0.19, 0.12, 0.23, 0.04),
                                        (0.13, 0.10, 0.30, 0.07),
                                        (0.07, 0.07, 0.35, 0.09))):
        whorl = rig.add_ring(f"Whorl{i}", (0.0, dy, dz), radius=r,
                             thickness=t, height=0.26,
                             material=m["plum"], verts=16)
        whorl.rotation_euler = (math.radians(74.0), 0.0, 0.0)
        parts.append(whorl)

    # The mouth of the shell, full of pigment. This is the bright bit.
    parts.append(rig.add_cylinder("Mouth", (0.0, -0.20, 0.17), radius=0.17,
                                  depth=0.10, material=m["teal"], verts=12,
                                  rotation=(math.radians(74.0), 0.0, 0.0)))
    parts.append(rig.add_sphere("Pigment", (0.0, -0.17, 0.18), 0.12,
                                m["teal"], segments=10, rings=6))

    # Smoke lifting off, as overlapping beads that thin out with height.
    rig.add_arc(parts, "Smoke", (0.0, -0.10, 0.34), radius=0.34,
                start_deg=-6.0, end_deg=84.0, bead_radius=0.085,
                material=m["teal_soft"], segments=7, plane="yz",
                squash=0.45, taper=0.30)
    return parts


# --------------------------------------------------------------------------
# Bullets
# --------------------------------------------------------------------------

def build_bullet(colour_hex, radius_m, with_trail):
    """
    A bullet is a flat, unshaded disc with a bright core.

    Deliberately NOT cel-shaded. The GDD's hardest rule is that enemy bullets
    must always read against the room, and cel shading would give a bullet a
    dark side that vanishes on a dark floor. Flat emission is the same colour
    from every angle and every position.
    """
    parts = []
    core = rig.flat_material("BulletCore", colour_hex, strength=1.0)
    halo_rgb = rig._mix_rgba(rig.hex_to_srgb(colour_hex),
                             rig.pal_srgb("parchment"), 0.45)
    halo = rig.flat_material("BulletHalo",
                             rig.srgb_to_linear_rgba(halo_rgb), strength=0.9)

    parts.append(rig.add_cylinder("BulletBody", (0.0, 0.0, radius_m),
                                  radius=radius_m, depth=radius_m * 0.5,
                                  material=core, verts=12))
    parts.append(rig.add_cylinder("BulletCore", (0.0, 0.0, radius_m * 1.3),
                                  radius=radius_m * 0.45,
                                  depth=radius_m * 0.5,
                                  material=halo, verts=10))
    if with_trail:
        # Tail along -Y, which is DOWN in the render, so the nose points UP
        # at rotation 0. EnemyBullet.gd does rotation = angle + PI/2, which
        # gives 0 for a bullet travelling up - so the sprite must already
        # point up in frame. Backwards here and every bullet flies tail-first.
        parts.append(rig.add_cone("BulletTail",
                                  (0.0, -radius_m * 1.45, radius_m),
                                  radius1=radius_m * 0.8, radius2=0.0,
                                  depth=radius_m * 1.8, material=core,
                                  verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    return parts


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

def _top_down_camera(size_m):
    for ob in list(bpy.data.objects):
        if ob.type == "CAMERA":
            bpy.data.objects.remove(ob, do_unlink=True)
    cam_data = bpy.data.cameras.new("TopCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = size_m
    cam = bpy.data.objects.new("TopCam", cam_data)
    bpy.context.collection.objects.link(cam)
    cam.location = (0.0, 0.0, 10.0)
    cam.rotation_euler = (0.0, 0.0, 0.0)
    bpy.context.scene.camera = cam


def render_prop(name, frame_px, builder, top_down=False, yaw_deg=45.0,
                ink=0.8):
    rig.clear_scene()
    rig.setup_render(frame_px=frame_px, subject_height_m=1.0,
                     frame_height_m=frame_m(frame_px))
    rig.set_ink(crease=False, material_boundary=True, thickness=ink)

    merged = rig.join_parts(builder(), name)
    pivot = rig.group_under_pivot([merged], f"{name}Pivot")
    pivot.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    if top_down:
        _top_down_camera(frame_m(frame_px))

    rig.render_single(rig.sprite_dir("props"), name)


def main():
    only = os.environ.get("ONLY")

    jobs = [
        ("barrel", 80, build_lamp_oil, {}),
        ("cover_intact", 112, lambda: build_tomes(0), {}),
        ("cover_cracked", 112, lambda: build_tomes(1), {}),
        ("cover_crumbling", 112, lambda: build_tomes(2), {}),
        ("trap_disarmed", 96, lambda: build_trap("disarmed"), {}),
        ("trap_armed", 96, lambda: build_trap("armed"), {}),
        ("trap_triggered", 96, lambda: build_trap("triggered"), {}),
        ("powerup_shell", 64, build_pigment_shell, {}),
        # Bullets render STRAIGHT DOWN at yaw 0. A disc seen at 45 deg is an
        # ellipse, so a bullet's apparent size would change with its heading -
        # and the GDD measures grazing at 20 px, which you cannot judge
        # against a target that changes size as it turns.
        ("bullet_enemy", 40, lambda: build_bullet("FF2E6E", 0.19, True),
         {"top_down": True, "yaw_deg": 0.0, "ink": 1.0}),
        ("bullet_player", 32, lambda: build_bullet("35D6C4", 0.14, True),
         {"top_down": True, "yaw_deg": 0.0, "ink": 0.9}),
    ]

    for name, frame_px, builder, kw in jobs:
        if only and only not in name:
            continue
        render_prop(name, frame_px, builder, **kw)

    print("[props] done ->", rig.sprite_dir("props"))


if __name__ == "__main__":
    main()
