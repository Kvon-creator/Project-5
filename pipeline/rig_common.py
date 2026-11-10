"""
Project 5 - shared Blender render rig.

Every asset in this game is rendered through THIS file so they all match.
The GDD's Art direction section is the spec; the constants below are that spec
turned into numbers.

    Pipeline: model and texture in Blender -> render with an orthographic camera
    at a fixed 3/4 angle, key light from the top-left -> 8-direction sprite
    sheets -> Godot AnimatedSprite2D.

Nothing here renders on its own. Asset scripts (player.py, enemy.py, ...)
import this, build geometry, and call `render_sheet()`.

Run an asset script with:
    blender -b --python pipeline/player.py
"""

import math
import os
import sys

import bpy
from mathutils import Vector

# --------------------------------------------------------------------------
# GDD constants
# --------------------------------------------------------------------------

# "Every distance is in pixels. The kickoff's 3 m barrel radius converts at
#  1 m = 32 px, so 96 px."
PX_PER_METRE = 32

# "fixed 3/4 top-down orthographic view"
#
# Elevation measured up from the floor plane. 45 deg is the balance point for
# this game: high enough that the floor, bullet positions and the 20 px graze
# window read clearly, low enough that a character still shows its FRONT and
# not just its hat. Tried 55 first and every character rendered as a bell
# shape, because vertical foreshortening at 55 deg is cos(55) = 0.57 - the
# model loses nearly half its height before the silhouette is even drawn.
# At 45 deg that factor is 0.71.
#
# Changing this changes every asset, so re-render the whole set if you touch
# it: ./pipeline/render_all.sh
CAMERA_ELEVATION_DEG = 45.0

# "8-direction sprite sheets". Index 0 is the anchor pose (facing down-right),
# then counter-clockwise in 45 deg steps. Godot reads the sheet left to right.
DIRECTIONS = ["SE", "E", "NE", "N", "NW", "W", "SW", "S"]
DIR_COUNT = len(DIRECTIONS)

# --------------------------------------------------------------------------
# Palette - from the GDD Palette table. Hex is authoritative, these are the
# linear-space floats Blender wants.
# --------------------------------------------------------------------------

PALETTE_HEX = {
    # --- SIGNAL -----------------------------------------------------------
    # Gameplay colours. These survived the art-direction change unaltered,
    # because the references already agreed with the GDD: the hero's nib
    # glows teal, the boss fires magenta, his plume is ember.
    "nib_teal": "35D6C4",         # Player shots, the pen-nib glow, power-ups
    "hostile_magenta": "FF2E6E",  # Enemy bullets. Nothing else, ever.
    "ember": "F06A2A",            # Hero plume, candle flame, barrels
    "graze_gold": "FFC93C",       # Graze Meter, graze sparks, Shockwave ring

    # --- WORLD ------------------------------------------------------------
    # Measured from docs/reference by pipeline/extract_palette.py. These are
    # LIGHTER and WARMER than the GDD's Crypt Stone / Stone Light, which were
    # written before the references existed.
    "parchment": "E2C5A8",        # Paper, cape, gilt filigree, UI text
    "candle_warm": "BE9E91",      # Stone near a candle
    "stone_lit": "8A8088",        # Floor in light - the room's main value
    "stone_mid": "776B70",        # Wall faces
    "stone_shadow": "554F59",     # Wall shadow, floor away from light
    "ink_violet": "3C2C39",       # Deep shadow, recesses
    "ink_black": "18030A",        # Ink pools, contour lines, the void
    "gilt": "C8A24E",             # Gold vine work on walls

    # --- CREATURE + HERO --------------------------------------------------
    "creature_violet": "886181",  # Enemy flesh, fur, slug bodies
    "creature_rust": "BA7977",    # Enemy hide, shells, cloth
    "deep_plum": "421C39",        # Enemy shadow side
    "steel": "868178",            # Hero armour
    "blood_rust": "8E2A2A",       # Traps, damage flashes

    # --- Legacy GDD names -------------------------------------------------
    # cel_material() mixes toward "abyss" for shadow and "bone" for highlight,
    # and older asset scripts still ask for these by name. Kept as aliases so
    # nothing silently breaks; new work should use the names above.
    "abyss": "18030A",            # -> ink_black
    "bone": "E2C5A8",             # -> parchment
    "crypt_stone": "554F59",      # -> stone_shadow
    "stone_light": "776B70",      # -> stone_mid
    "spirit_teal": "35D6C4",      # -> nib_teal
}


def srgb_to_linear(c: float) -> float:
    """Blender works in linear light; hex codes are sRGB."""
    if c <= 0.04045:
        return c / 12.92
    return ((c + 0.055) / 1.055) ** 2.4


def hex_to_srgb(hex_str: str, alpha: float = 1.0):
    """Hex -> sRGB floats. This is the space the palette is DEFINED in."""
    hex_str = hex_str.lstrip("#")
    return tuple(int(hex_str[i:i + 2], 16) / 255.0
                 for i in (0, 2, 4)) + (alpha,)


def srgb_to_linear_rgba(srgb):
    """sRGB floats -> linear floats. Alpha is already linear, leave it."""
    return tuple(srgb_to_linear(c) for c in srgb[:3]) + (srgb[3],)


def hex_to_rgba(hex_str: str, alpha: float = 1.0):
    """Hex -> linear floats, ready to hand to Blender."""
    return srgb_to_linear_rgba(hex_to_srgb(hex_str, alpha))


def pal(name: str, alpha: float = 1.0):
    """Palette lookup by GDD swatch name, in linear space."""
    return hex_to_rgba(PALETTE_HEX[name], alpha)


def pal_srgb(name: str, alpha: float = 1.0):
    """Palette lookup by GDD swatch name, in sRGB space."""
    return hex_to_srgb(PALETTE_HEX[name], alpha)


# --------------------------------------------------------------------------
# Scene setup
# --------------------------------------------------------------------------

def clear_scene() -> None:
    """Blender starts with a cube, a camera and a light. Remove all of it."""
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials, bpy.data.lights,
                  bpy.data.cameras, bpy.data.images):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def setup_render(frame_px: int, subject_height_m: float,
                 frame_height_m: float) -> None:
    """
    Configure EEVEE, the orthographic camera and the lights.

    frame_px          - sprite frame is frame_px x frame_px (e.g. 128)
    subject_height_m  - how tall the model is in metres (unused by the camera,
                        kept so asset scripts document their own scale)
    frame_height_m    - how many metres the frame covers top to bottom. This is
                        what sets the pixels-per-metre of the final sprite.

    A 128 px frame covering 4 m gives 32 px/m, which matches PX_PER_METRE, so
    a 2 m tall player lands at 64 px - the anchor asset spec.
    """
    scene = bpy.context.scene

    # EEVEE, because the cel shader below needs Shader-to-RGB, which Cycles
    # does not support. The engine id was renamed across Blender versions
    # (BLENDER_EEVEE -> BLENDER_EEVEE_NEXT in 4.2, back to BLENDER_EEVEE in
    # 5.0), so pick whichever this build offers.
    engines = scene.render.bl_rna.properties["engine"].enum_items.keys()
    for candidate in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        if candidate in engines:
            scene.render.engine = candidate
            break
    else:
        raise RuntimeError(f"No EEVEE engine in this Blender: {list(engines)}")
    scene.render.resolution_x = frame_px
    scene.render.resolution_y = frame_px
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"

    # "plain background" - transparent, so sprites composite over the tiles.
    scene.render.film_transparent = True

    # Avoid list: "Bloom, glow or particle effects that hide bullets or the
    # player hitbox." Newer EEVEE has no bloom pass at all; older builds do,
    # and raytracing would soften the flat cel bands. Both are version
    # dependent, so set only what this build actually has.
    for attr, value in (("use_raytracing", False), ("use_bloom", False),
                        ("use_gtao", False)):
        if hasattr(scene.eevee, attr):
            setattr(scene.eevee, attr, value)

    # "Standard" view transform, not Filmic/AgX: the palette hexes must come
    # out of the render as the hexes the GDD specifies, not tone-mapped.
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"

    # Crisp sprite edges: no filtering blur beyond one pixel.
    scene.render.filter_size = 1.0

    _add_camera(frame_height_m)
    _add_lights()
    _setup_freestyle()


def _add_camera(frame_height_m: float) -> None:
    """
    Orthographic camera, fixed 3/4 top-down, aimed at the origin.

    The camera never moves between directions. Asset scripts rotate the MODEL
    instead, which is what keeps the light direction constant across all eight
    frames - the thing that makes a sheet look like one character.
    """
    cam_data = bpy.data.cameras.new("SpriteCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = frame_height_m

    cam = bpy.data.objects.new("SpriteCam", cam_data)
    bpy.context.collection.objects.link(cam)

    # Place the camera on the -Y side, elevated, looking at the origin.
    elev = math.radians(CAMERA_ELEVATION_DEG)
    dist = 12.0
    cam.location = (0.0,
                    -dist * math.cos(elev),
                    dist * math.sin(elev))
    # Point it at the origin: tilt down from straight-down by the elevation.
    cam.rotation_euler = (math.radians(90.0) - elev, 0.0, 0.0)

    bpy.context.scene.camera = cam


def _add_lights() -> None:
    """
    "strong top-left key light and warm rim light"

    Key from the top-left so every asset's shadow falls the same way. The rim
    is warm and comes from behind-right to lift the silhouette off dark floors.
    """
    # Energies are tuned to the 3-band ramp in cel_material(), not to realism.
    # A Diffuse BSDF with albedo 1 turns sun irradiance E into radiance E/pi,
    # so a face pointing straight at a 2.8 W sun reads 0.89 - just inside the
    # top band - while a face at 45 deg reads 0.63 (mid band) and anything
    # past 70 deg falls to shadow. That is what gives three visible steps
    # instead of one flat silhouette.
    key_data = bpy.data.lights.new("Key", type="SUN")
    key_data.energy = 2.8
    key_data.color = (1.0, 0.95, 0.88)      # near-white, a touch warm
    key_data.angle = math.radians(8.0)      # slightly soft terminator
    key = bpy.data.objects.new("Key", key_data)
    bpy.context.collection.objects.link(key)
    # Top-left: comes down from +Z, from the -X side.
    key.rotation_euler = (math.radians(50.0), math.radians(-35.0),
                          math.radians(25.0))

    rim_data = bpy.data.lights.new("Rim", type="SUN")
    rim_data.energy = 1.4
    rim_data.color = hex_to_rgba(PALETTE_HEX["ember"])[:3]  # warm rim
    rim = bpy.data.objects.new("Rim", rim_data)
    bpy.context.collection.objects.link(rim)
    # Behind and to the right, low, grazing the back edge.
    rim.rotation_euler = (math.radians(105.0), math.radians(30.0),
                          math.radians(200.0))

    # A dim fill so the shadow side is readable rather than pure black. Kept
    # cool so it sits in the Abyss / Crypt Stone end of the palette.
    fill_data = bpy.data.lights.new("Fill", type="SUN")
    fill_data.energy = 1.15
    fill_data.color = (0.45, 0.42, 0.62)
    fill = bpy.data.objects.new("Fill", fill_data)
    bpy.context.collection.objects.link(fill)
    fill.rotation_euler = (math.radians(70.0), math.radians(40.0),
                           math.radians(-120.0))


def _setup_freestyle() -> None:
    """
    "bold dark ink outlines"

    Freestyle draws real line art over the render. Silhouette + border gives
    the outer ink line; crease picks up the hard folds on a low-poly model.
    """
    scene = bpy.context.scene
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    # 1.6 px at a 128 px frame: bold enough to read when the sprite is on a
    # dark floor, thin enough not to eat a 64 px character.
    scene.render.line_thickness = 1.6

    view_layer = scene.view_layers[0]
    view_layer.use_freestyle = True
    view_layer.freestyle_settings.mode = "EDITOR"

    # A fresh Blender scene ships with one empty line set; reuse or add.
    fs = view_layer.freestyle_settings
    if not fs.linesets:
        fs.linesets.new("InkLines")
    lineset = fs.linesets[0]
    lineset.select_silhouette = True
    lineset.select_border = True
    lineset.select_crease = True
    lineset.select_edge_mark = True
    lineset.select_contour = False
    lineset.select_material_boundary = True

    linestyle = lineset.linestyle
    linestyle.color = hex_to_rgba(PALETTE_HEX["abyss"])[:3]  # ink = Abyss
    linestyle.thickness = 1.6
    linestyle.alpha = 1.0
    # Slight taper so the line feels drawn rather than traced.
    linestyle.thickness_position = "CENTER"


def set_ink(crease=True, material_boundary=True, thickness=None,
            silhouette=True, border=True):
    """
    Tune the Freestyle line work after setup_render().

    Why this is a knob rather than a constant: a character built from two
    dozen primitives generates a crease line at every box corner, and at
    64 px those interior lines merge into a black mass - the figure stops
    reading as armour and becomes a blob. Environments are the opposite
    case: they are large flat surfaces where crease lines are most of the
    drawing.

    So characters use crease=False (outline and colour boundaries only) and
    rooms leave it on.
    """
    scene = bpy.context.scene
    if thickness is not None:
        scene.render.line_thickness = thickness
    lineset = scene.view_layers[0].freestyle_settings.linesets[0]
    lineset.select_silhouette = silhouette
    lineset.select_border = border
    lineset.select_crease = crease
    lineset.select_material_boundary = material_boundary
    if thickness is not None:
        lineset.linestyle.thickness = thickness


# --------------------------------------------------------------------------
# Cel-shaded material
# --------------------------------------------------------------------------

def cel_material(name: str, base_hex_or_rgba, shadow_mix: float = 0.45,
                 highlight_mix: float = 0.30, bands: int = 3,
                 emission_strength: float = 1.0):
    """
    "cel-shaded with painterly brushstroke highlights"

    How it works, in order:
      1. A Diffuse BSDF gathers the real lighting from the three lamps.
      2. Shader-to-RGB turns that lighting into a plain colour value. This is
         the EEVEE-only trick that makes stylised shading possible at all.
      3. A ColorRamp with CONSTANT interpolation snaps that smooth gradient
         into `bands` hard steps - the cel look.
      4. The steps are used to mix between a darkened and a lightened version
         of the base colour, so every material stays inside its own hue.
      5. Emission outputs the result, so the bands are not re-lit.

    base_hex_or_rgba - a GDD hex string or an RGBA tuple
    shadow_mix       - how far the dark band moves toward Abyss (0..1)
    highlight_mix    - how far the lit band moves toward Bone (0..1)
    bands            - number of hard shading steps
    """
    # Work in sRGB for the palette mixing below, because the GDD's swatches are
    # sRGB hex codes and "25% toward Bone" has to mean 25% the way a person
    # reading the palette would expect. Mixing in linear space instead lands
    # far brighter and washes the hue out, because Bone's linear value is
    # roughly nine times Stone Light's.
    if isinstance(base_hex_or_rgba, str):
        base_srgb = hex_to_srgb(base_hex_or_rgba)
    else:
        base_srgb = tuple(base_hex_or_rgba)
        if len(base_srgb) == 3:
            base_srgb = base_srgb + (1.0,)

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()

    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (900, 0)

    diffuse = nt.nodes.new("ShaderNodeBsdfDiffuse")
    diffuse.location = (-600, 0)
    diffuse.inputs["Color"].default_value = (1.0, 1.0, 1.0, 1.0)

    to_rgb = nt.nodes.new("ShaderNodeShaderToRGB")
    to_rgb.location = (-400, 0)
    nt.links.new(diffuse.outputs["BSDF"], to_rgb.inputs["Shader"])

    # Collapse RGB lighting to one luminance value before banding, so coloured
    # lights do not split one band into three.
    lum = nt.nodes.new("ShaderNodeRGBToBW")
    lum.location = (-220, 0)
    nt.links.new(to_rgb.outputs["Color"], lum.inputs["Color"])

    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.location = (-40, 0)
    ramp.color_ramp.interpolation = "CONSTANT"
    _build_bands(ramp.color_ramp, bands)
    nt.links.new(lum.outputs["Val"], ramp.inputs["Fac"])

    # Darkened and lightened versions of the base colour. Mixed in sRGB, then
    # converted to linear once, at the end.
    shadow_rgba = srgb_to_linear_rgba(
        _mix_rgba(base_srgb, pal_srgb("abyss"), shadow_mix))
    light_rgba = srgb_to_linear_rgba(
        _mix_rgba(base_srgb, pal_srgb("bone"), highlight_mix))

    mix = nt.nodes.new("ShaderNodeMixRGB")
    mix.location = (300, 0)
    mix.blend_type = "MIX"
    mix.inputs["Color1"].default_value = shadow_rgba
    mix.inputs["Color2"].default_value = light_rgba
    nt.links.new(ramp.outputs["Color"], mix.inputs["Fac"])

    emit = nt.nodes.new("ShaderNodeEmission")
    emit.location = (620, 0)
    emit.inputs["Strength"].default_value = emission_strength
    nt.links.new(mix.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])

    return mat


def _build_bands(ramp, bands: int) -> None:
    """Lay out `bands` evenly spaced hard steps from black to white."""
    while len(ramp.elements) > 1:
        ramp.elements.remove(ramp.elements[-1])
    ramp.elements[0].position = 0.0
    ramp.elements[0].color = (0.0, 0.0, 0.0, 1.0)
    for i in range(1, bands):
        pos = i / float(bands)
        value = i / float(bands - 1) if bands > 1 else 1.0
        el = ramp.elements.new(pos)
        el.color = (value, value, value, 1.0)


def _mix_rgba(a, b, factor: float):
    return tuple(a[i] * (1.0 - factor) + b[i] * factor for i in range(4))


def flat_material(name: str, base_hex_or_rgba, strength: float = 1.0):
    """
    Unshaded emission. For things that must read as one solid colour at every
    angle - enemy bullets above all, where the GDD is strict: "Hostile Magenta
    appears on enemy bullets and nothing else, so bullets always read against
    the room."
    """
    if isinstance(base_hex_or_rgba, str):
        base = hex_to_rgba(base_hex_or_rgba)
    else:
        base = tuple(base_hex_or_rgba)
        if len(base) == 3:
            base = base + (1.0,)

    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = base
    emit.inputs["Strength"].default_value = strength
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    return mat


# --------------------------------------------------------------------------
# Geometry helpers - low-poly primitives, kept blocky on purpose
# --------------------------------------------------------------------------

def add_box(name, location, size, material=None, rotation=(0, 0, 0)):
    """
    A box whose final extent really is `size`, in metres.

    Note the scale factor. `primitive_cube_add(size=1.0)` already produces a
    cube one unit on a side, spanning -0.5 to +0.5 - NOT the default 2-unit
    cube. So the scale needed to reach `size` is `size`, not `size / 2`.
    Using `size / 2` here silently halves every box in the project, which is
    a quiet bug: the models still render, they just come out wrong, and the
    parts most affected are the thin ones - arms, legs, seams - which simply
    stop being visible rather than looking obviously broken.
    """
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=location)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size[0], size[1], size[2])
    ob.rotation_euler = rotation
    if material:
        ob.data.materials.append(material)
    _flat_shade(ob)
    return ob


def add_cylinder(name, location, radius, depth, material=None, verts=8,
                 rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=radius,
                                        depth=depth, location=location)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = rotation
    if material:
        ob.data.materials.append(material)
    _flat_shade(ob)
    return ob


def add_sphere(name, location, radius, material=None, segments=10, rings=6):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=radius, location=location)
    ob = bpy.context.active_object
    ob.name = name
    if material:
        ob.data.materials.append(material)
    _flat_shade(ob)
    return ob


def add_ring(name, location, radius, thickness, height, material=None,
             verts=48):
    """
    A flat annulus - a ring with a genuine hole, not a disc.

    Floor inlay needs this. Faking a ring by stacking a smaller disc on top
    of a larger one only works for the outermost ring; any ring inside it
    gets buried by the disc above.
    """
    bpy.ops.mesh.primitive_torus_add(
        location=location,
        major_radius=radius,
        minor_radius=thickness * 0.5,
        major_segments=verts,
        minor_segments=4,
    )
    ob = bpy.context.active_object
    ob.name = name
    # Squash the tube flat so it sits in the floor rather than on it.
    ob.scale = (1.0, 1.0, height / max(thickness, 1e-6))
    if material:
        ob.data.materials.append(material)
    _flat_shade(ob)
    return ob


def add_cone(name, location, radius1, radius2, depth, material=None, verts=8,
             rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=radius1,
                                    radius2=radius2, depth=depth,
                                    location=location)
    ob = bpy.context.active_object
    ob.name = name
    ob.rotation_euler = rotation
    if material:
        ob.data.materials.append(material)
    _flat_shade(ob)
    return ob


def _flat_shade(ob) -> None:
    """Low-poly means visible facets. Kill any auto-smoothing."""
    for poly in ob.data.polygons:
        poly.use_smooth = False


# --------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------

def join_parts(parts, name="Merged"):
    """
    Join every part into ONE mesh, and return it.

    This matters more than it looks. Freestyle draws a silhouette around each
    separate OBJECT, so a character assembled from two dozen primitives gets
    two dozen outlines - one around every box, including the ones buried
    inside the body. At 64 px those stack into a black mass and the figure
    stops reading as armour.

    Joined into a single mesh, "silhouette" means the figure's true outer
    contour, which is what an inked drawing actually has. Interior detail
    then comes from material boundaries alone, at whatever weight suits.

    World positions are preserved: join() rewrites each object's vertices
    through the active object's inverse world matrix.
    """
    if not parts:
        raise ValueError("join_parts: nothing to join")

    bpy.ops.object.select_all(action="DESELECT")
    for ob in parts:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()

    merged = bpy.context.view_layer.objects.active
    merged.name = name
    _flat_shade(merged)
    return merged


def group_under_pivot(objects, pivot_name="Pivot"):
    """
    Parent everything to one empty at the origin, so a single Z rotation on
    that empty turns the whole model for the 8-direction sheet.
    """
    pivot = bpy.data.objects.new(pivot_name, None)
    bpy.context.collection.objects.link(pivot)
    pivot.location = (0.0, 0.0, 0.0)
    for ob in objects:
        ob.parent = pivot
    return pivot


def render_sheet(pivot, out_dir, asset_name, directions=None,
                 start_yaw_deg=0.0):
    """
    Render one PNG per direction into out_dir as <asset>_<DIR>.png.

    The anchor direction (index 0, "SE" - facing down-right) is rendered first
    and also written as <asset>_anchor.png, because the GDD checks every other
    asset against that frame.

    Blender has no way to write a packed sprite strip itself, so the frames go
    out one per file and pack.py stitches them. Godot's AnimatedSprite2D is
    happy with either.
    """
    directions = directions or DIRECTIONS
    os.makedirs(out_dir, exist_ok=True)
    scene = bpy.context.scene

    written = []
    for i, name in enumerate(directions):
        # Model yaw. The camera sits on -Y, so yaw 0 shows the model's -Y face.
        # Rotating the model counter-clockwise walks through the 8 directions.
        yaw = start_yaw_deg + (360.0 / len(directions)) * i
        pivot.rotation_euler = (0.0, 0.0, math.radians(yaw))

        path = os.path.join(out_dir, f"{asset_name}_{name}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        written.append(path)
        print(f"[render] {asset_name} {name} -> {path}")

    # The anchor frame, duplicated under a stable name.
    anchor_src = os.path.join(out_dir, f"{asset_name}_{directions[0]}.png")
    anchor_dst = os.path.join(out_dir, f"{asset_name}_anchor.png")
    if os.path.exists(anchor_src):
        with open(anchor_src, "rb") as fsrc, open(anchor_dst, "wb") as fdst:
            fdst.write(fsrc.read())
        print(f"[render] anchor -> {anchor_dst}")

    return written


def render_single(out_dir, asset_name):
    """One frame, no turntable. For bullets, tiles and anything symmetrical."""
    os.makedirs(out_dir, exist_ok=True)
    path = os.path.join(out_dir, f"{asset_name}.png")
    bpy.context.scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"[render] {asset_name} -> {path}")
    return path


def repo_root() -> str:
    """Absolute path to the repo, regardless of where blender was launched."""
    here = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(here)


def sprite_dir(*parts) -> str:
    return os.path.join(repo_root(), "assets", "sprites", *parts)
