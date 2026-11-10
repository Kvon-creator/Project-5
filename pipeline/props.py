"""
Bullets and the three interactive objects.

GDD, Environmental Combat (K'von Gates):
    Explosive barrel   Detonates after 2 hits; 30 damage within 96 px (3 m)
    Destructible cover Blocks enemy bullets; breaks after 5 hits from any source
    Trap               Triggers when stepped on: 15 damage; re-arms after 2 s

Everything here is rendered through the same rig as the anchor asset, at the
same pixels-per-metre, so a barrel standing next to the player is the right
size without anyone eyeballing it.

Run:
    blender -b --python pipeline/props.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import rig_common as rig  # noqa: E402

# Pixels per metre, inherited from the anchor asset: 128 px frame / 3.90 m.
PX_PER_M = 128 / 3.90


def frame_m(frame_px: int) -> float:
    """Metres a frame of `frame_px` covers, at the anchor's pixels-per-metre."""
    return frame_px / PX_PER_M


# --------------------------------------------------------------------------
# Bullets
# --------------------------------------------------------------------------

def build_bullet(colour_hex: str, radius_m: float, with_trail: bool):
    """
    A bullet is a flat, unshaded disc with a bright core.

    Deliberately NOT cel-shaded. The GDD's hardest art rule is that enemy
    bullets must always read against the room, and cel shading would give a
    bullet a dark side that disappears against a dark floor. A flat emission
    disc is the same colour from every angle, at every position in the room.

    The avoid list also bans "Bloom, glow or particle effects that hide
    bullets", so the "glow" here is a second, larger disc at low opacity
    rather than a real glow - it reads as a soft edge without ever obscuring
    the bullet's true position, which is what the 20 px graze window is
    measured from.
    """
    parts = []

    core = rig.flat_material("BulletCore", colour_hex, strength=1.0)
    # The halo is the same hue lifted toward Bone, so it stays on-palette.
    halo_rgb = rig._mix_rgba(rig.hex_to_srgb(colour_hex),
                             rig.pal_srgb("bone"), 0.45)
    halo = rig.flat_material("BulletHalo",
                             rig.srgb_to_linear_rgba(halo_rgb), strength=0.9)

    # Flat disc facing the camera. A sphere would shade itself at the edges
    # even with emission, because Freestyle would outline the silhouette
    # differently per angle.
    parts.append(rig.add_cylinder("BulletBody", (0.0, 0.0, radius_m),
                                  radius=radius_m, depth=radius_m * 0.5,
                                  material=core, verts=12))
    # Bright centre, so the exact pixel the hitbox sits on is the brightest.
    parts.append(rig.add_cylinder("BulletCore", (0.0, 0.0, radius_m * 1.3),
                                  radius=radius_m * 0.45,
                                  depth=radius_m * 0.5,
                                  material=halo, verts=10))

    if with_trail:
        # The tail runs along -Y in Blender, which is DOWN in the rendered
        # image, so the bullet's nose points UP at rotation 0.
        #
        # That matches what EnemyBullet.gd does:
        #     rotation = direction.angle() + PI/2
        # A bullet travelling up is Vector2(0, -1), whose angle is -PI/2, so
        # the expression gives rotation 0 - which has to be the frame where
        # the sprite already points up. Get this backwards and every bullet
        # in the game flies tail-first.
        parts.append(rig.add_cone("BulletTail",
                                  (0.0, -radius_m * 1.45, radius_m),
                                  radius1=radius_m * 0.8, radius2=0.0,
                                  depth=radius_m * 1.8, material=core,
                                  verts=8,
                                  rotation=(math.radians(90.0), 0.0, 0.0)))
    return parts


def render_bullets():
    # Bullets are the one prop rendered STRAIGHT DOWN at yaw 0, not through
    # the 3/4 rig. Three reasons, all of them about the graze window:
    #
    #   - A disc seen at 45 deg is an ellipse, so the bullet's apparent size
    #     would change with its heading. The GDD measures grazing at 20 px
    #     from the player hitbox; a bullet that is 12 px wide one way and
    #     8 px the other makes that threshold impossible to judge by eye.
    #   - Rendered at a 45 deg yaw the sprite comes out off-centre in its
    #     frame, so rotating it in Godot would swing it around the wrong
    #     pivot and the bullet would wobble as it flew.
    #   - Bullets use flat emission anyway, so they gain nothing from the
    #     3/4 lighting.
    #
    # GDD: "Hostile Magenta #FF2E6E - Enemy bullets only". About 12 px wide,
    # which sits well inside the 20 px graze ring: the player can see both
    # the bullet and the gap they are threading.
    _render_prop("bullet_enemy", 40,
                 lambda: build_bullet("FF2E6E", 0.19, True),
                 freestyle=True, line_px=1.0, top_down=True, yaw_deg=0.0)

    # Player shot. GDD: "Spirit Teal #35D6C4 - Player shots, damage power-up".
    # Smaller than an enemy bullet, so a screen full of both still reads.
    _render_prop("bullet_player", 32,
                 lambda: build_bullet("35D6C4", 0.14, True),
                 freestyle=True, line_px=0.9, top_down=True, yaw_deg=0.0)


# --------------------------------------------------------------------------
# Explosive barrel
# --------------------------------------------------------------------------

def build_barrel():
    """
    GDD: "Explosive barrel - Detonates after 2 hits; 30 damage to enemies
    within 96 px (3 m)".

    Ember, per the palette table ("Ember: Player accents, explosive barrels,
    fire"). The banding is deliberate: a barrel has to read as an explosive
    at a glance, because the player decides whether to shoot it while dodging.
    """
    body = rig.cel_material("BarrelBody", "F06A2A",
                            shadow_mix=0.45, highlight_mix=0.22)
    band = rig.cel_material("BarrelBand", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.25)
    cap = rig.cel_material("BarrelCap", "4E4458",
                           shadow_mix=0.40, highlight_mix=0.24)

    parts = []
    # 0.95 m tall, 0.62 m across - roughly waist-high on the 2 m player.
    parts.append(rig.add_cylinder("Body", (0.0, 0.0, 0.47), radius=0.31,
                                  depth=0.95, material=body, verts=10))
    # Two dark hoops. These also break up the Ember so a barrel is not
    # mistaken for the player's accent colour at distance.
    for z in (0.26, 0.68):
        parts.append(rig.add_cylinder(f"Hoop{int(z * 100)}", (0.0, 0.0, z),
                                      radius=0.325, depth=0.09,
                                      material=band, verts=10))
    parts.append(rig.add_cylinder("Cap", (0.0, 0.0, 0.97), radius=0.27,
                                  depth=0.07, material=cap, verts=10))
    parts.append(rig.add_cylinder("Valve", (0.0, 0.0, 1.03), radius=0.09,
                                  depth=0.08, material=band, verts=8))
    return parts


# --------------------------------------------------------------------------
# Destructible cover
# --------------------------------------------------------------------------

def build_cover(damage_stage: int):
    """
    GDD: "Destructible cover - Blocks enemy bullets; breaks after 5 hits from
    any source". Stone Light, per the palette ("Walls, destructible cover").

    Three damage stages are rendered - intact, cracked, crumbling - so the
    player can see how many hits a piece of cover has left. That readability
    matters because of the cross-link in the GDD: "Shockwave clears bullets
    the way cover blocks them, so the player can trade cover for a
    Shockwave." You cannot make that trade if you cannot tell how close the
    cover is to breaking.

    damage_stage: 0 intact (0-1 hits), 1 cracked (2-3), 2 crumbling (4-5)
    """
    stone = rig.cel_material(f"CoverStone{damage_stage}", "4E4458",
                             shadow_mix=0.45, highlight_mix=0.24)
    dark = rig.cel_material(f"CoverDark{damage_stage}", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.20)

    parts = []
    # A 1.5 m wide, 1.1 m tall block: tall enough to hide a crouching enemy,
    # short enough that the player can see over it.
    height = [1.10, 0.98, 0.80][damage_stage]
    parts.append(rig.add_box("Slab", (0.0, 0.0, height * 0.5),
                             (1.50, 0.55, height), stone))
    # A capstone, so the top edge catches a separate ink line.
    parts.append(rig.add_box("Cap", (0.0, 0.0, height + 0.05),
                             (1.58, 0.63, 0.10), stone))

    if damage_stage >= 1:
        # Cracks: dark wedges bitten out of the face.
        for i, (x, z, w) in enumerate(((-0.42, 0.72, 0.16),
                                       (0.26, 0.48, 0.13))):
            parts.append(rig.add_box(f"Crack{i}", (x, -0.26, z * height),
                                     (w, 0.10, 0.30), dark,
                                     rotation=(0.0, math.radians(14.0), 0.0)))
    if damage_stage >= 2:
        # Crumbling: a corner is gone and rubble sits at the base.
        parts.append(rig.add_box("Breach", (0.56, -0.10, height * 0.86),
                                 (0.42, 0.70, 0.34), dark,
                                 rotation=(0.0, math.radians(-20.0), 0.0)))
        for i, x in enumerate((-0.62, 0.10, 0.70)):
            parts.append(rig.add_box(f"Rubble{i}", (x, -0.36, 0.07),
                                     (0.22, 0.20, 0.14), stone,
                                     rotation=(0.0, 0.0,
                                               math.radians(20.0 * i))))
    return parts


# --------------------------------------------------------------------------
# Trap
# --------------------------------------------------------------------------

def build_trap(armed: bool):
    """
    GDD: "Trap - Triggers when stepped on: 15 damage to the enemy or player on
    it; re-arms after 2 s (proposed)". Blood Rust, per the palette ("Traps,
    damage flashes").

    Two states, because the 2 s re-arm window is something the player has to
    read off the floor mid-fight. Armed shows live spikes and a lit rune;
    disarmed shows the plate flush and dark. Jarman's Enemy Adaptation also
    depends on this being visible: enemies "steer clear of active hazards
    within 75 px", so a player needs to see which traps are currently active
    to know where enemies will refuse to walk.
    """
    plate = rig.cel_material(f"TrapPlate{armed}", "2B2335",
                             shadow_mix=0.35, highlight_mix=0.28)
    rust = rig.cel_material(f"TrapRust{armed}", "8E2A2A",
                            shadow_mix=0.35, highlight_mix=0.30)
    dark = rig.cel_material(f"TrapDark{armed}", "120E1A",
                            shadow_mix=0.0, highlight_mix=0.18)

    parts = []
    # A 1.3 m floor plate, sitting almost flush so it never hides a bullet.
    parts.append(rig.add_box("Plate", (0.0, 0.0, 0.035), (1.30, 1.30, 0.07),
                             plate))
    parts.append(rig.add_box("Rim", (0.0, 0.0, 0.075), (1.38, 1.38, 0.05),
                             dark))

    if armed:
        # Spikes up, in Blood Rust.
        for ix in (-1, 0, 1):
            for iy in (-1, 0, 1):
                parts.append(rig.add_cone(f"Spike{ix}{iy}",
                                          (ix * 0.34, iy * 0.34, 0.21),
                                          radius1=0.09, radius2=0.0,
                                          depth=0.28, material=rust,
                                          verts=6))
    else:
        # Spikes retracted: flat sockets only, so the plate reads as safe.
        for ix in (-1, 0, 1):
            for iy in (-1, 0, 1):
                parts.append(rig.add_cylinder(f"Socket{ix}{iy}",
                                              (ix * 0.34, iy * 0.34, 0.075),
                                              radius=0.085, depth=0.03,
                                              material=dark, verts=6))
    return parts


# --------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------

def _top_down_camera(size_m: float) -> None:
    """Swap the 3/4 camera for one looking straight down."""
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


def _render_prop(name, frame_px, builder, freestyle=True, line_px=1.6,
                 turntable=False, out_sub="props", top_down=False,
                 yaw_deg=45.0):
    rig.clear_scene()
    rig.setup_render(frame_px=frame_px, subject_height_m=1.0,
                     frame_height_m=frame_m(frame_px))
    bpy.context.scene.render.use_freestyle = freestyle
    bpy.context.scene.render.line_thickness = line_px

    parts = builder()
    pivot = rig.group_under_pivot(parts, f"{name}Pivot")

    out_dir = rig.sprite_dir(out_sub)
    if turntable:
        rig.render_sheet(pivot, out_dir, name, start_yaw_deg=45.0)
    else:
        # Props are rendered at the anchor's 45 deg yaw so their lighting
        # matches characters standing next to them. Bullets are the
        # exception - see render_bullets().
        pivot.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
        if top_down:
            _top_down_camera(frame_m(frame_px))
        rig.render_single(out_dir, name)


def main():
    render_bullets()

    _render_prop("barrel", 64, build_barrel)

    for stage, label in enumerate(("intact", "cracked", "crumbling")):
        _render_prop(f"cover_{label}", 96,
                     lambda s=stage: build_cover(s))

    _render_prop("trap_armed", 64, lambda: build_trap(True))
    _render_prop("trap_disarmed", 64, lambda: build_trap(False))

    print("[props] done ->", rig.sprite_dir("props"))


if __name__ == "__main__":
    main()
