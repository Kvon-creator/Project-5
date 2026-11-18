#!/usr/bin/env python3
"""
Generate the Godot scenes from the rendered sprites.

Why a generator instead of hand-written .tscn files: every character needs a
SpriteFrames resource with eight animations, each pointing at its own PNG.
That is 8 ExtResource lines and 8 animation dictionaries per character, and
the moment a sprite is renamed or a tier is added, all of it has to be
retyped. The generator keeps the scene tree and the sprite set in step.

The generated .tscn files ARE committed - Godot needs them, and they should
be reviewable in a diff. Re-run this after changing sprite names or sizes:

    python3 pipeline/make_scenes.py

It does not overwrite anything under scripts/.
"""

import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES = os.path.join(ROOT, "scenes")

DIRECTIONS = ["SE", "E", "NE", "N", "NW", "W", "SW", "S"]

# --------------------------------------------------------------------------
# Measurements, taken from the rendered sprites with pipeline/check_anchor.py
# --------------------------------------------------------------------------

# The anchor sprite is a 128 px frame whose content runs y 9..73, so the
# character's feet sit 9 px BELOW the frame centre. Godot centres a sprite on
# its node origin, so the sprite is offset up by that much to put the node
# origin at the feet. That is what makes a character stand on a tile instead
# of hovering, and what makes the Y-sort order correct.
PLAYER_SPRITE_OFFSET_Y = -9

# Hitboxes are deliberately much smaller than the sprites. This is a bullet
# hell: the GDD's 20 px graze window only means something if the hitbox the
# player is threading is small and predictable. A hitbox the size of the
# cloak would make grazing impossible to judge.
PLAYER_HITBOX_RADIUS = 8
GRAZE_DISTANCE_PX = 20          # GDD: "within 20 px of the player hitbox"

ENEMY_HITBOX_RADIUS = {"snail": 14, "hare": 11, "grotesque": 18, "scribe": 30}
# Measured, not guessed. Godot centres a sprite on its node origin, so the
# offset is (frame_centre - content_base): how far the feet sit below the
# middle of the frame. Get this wrong and the character hovers or sinks.
# Values from pipeline/check_anchor.py:
#   snail      160 frame, content base y 105  -> 80 - 105 = -25
#   hare       128 frame, content base y  74  -> 64 -  74 = -10
#   grotesque  160 frame, content base y 100  -> 80 - 100 = -20
#   scribe     256 frame, content base y 155  -> 128 - 155 = -27
ENEMY_SPRITE_OFFSET_Y = {"snail": -25, "hare": -10, "grotesque": -20,
                         "scribe": -27}

ENEMY_BULLET_RADIUS = 5
PLAYER_BULLET_RADIUS = 4

# Which sprite set the character and prop scenes use.
#   "refs"    - the reference paintings, cut out by pipeline/cutout_refs.py.
#               One side view per creature; the scripts mirror it for
#               left-facing. This is the current look of the game.
#   "blender" - the 8-direction renders from player.py / enemy.py / props.py.
SPRITE_SET = "refs"

# Per cut-out: where the sprite sits over the feet (y offset of its centre)
# and the shadow ellipse under it, as a scale of the 64 px shadow texture.
REF_SPRITES = {
    "hero":      {"offset_y": -36, "shadow": (1.10, 0.36)},
    "snail":     {"offset_y": -26, "shadow": (1.50, 0.42)},
    "hare":      {"offset_y": -40, "shadow": (1.00, 0.32)},
    "grotesque": {"offset_y": -44, "shadow": (1.70, 0.50)},
    "scribe":    {"offset_y": -86, "shadow": (1.90, 0.60)},
    "lamp_oil":  {"offset_y": -22, "shadow": (0.70, 0.25)},
    "tome":      {"offset_y": -20, "shadow": (0.85, 0.30)},
    "trap":      {"offset_y": -16, "shadow": None},
    "shell":     {"offset_y": -18, "shadow": (0.80, 0.28)},
}

# The soft shadow every character and prop stands on: a radial gradient,
# scaled per sprite into an ellipse. Two sub-resources.
SHADOW_SUBS = [
    '[sub_resource type="Gradient" id="Grad_shadow"]\n'
    'offsets = PackedFloat32Array(0, 0.55, 1)\n'
    'colors = PackedColorArray(0, 0, 0, 1, 0, 0, 0, 0.55, 0, 0, 0, 0)\n',
    '[sub_resource type="GradientTexture2D" id="Tex_shadow"]\n'
    'gradient = SubResource("Grad_shadow")\n'
    'width = 64\nheight = 64\nfill = 1\n'
    'fill_from = Vector2(0.5, 0.5)\nfill_to = Vector2(0.5, 0)\n',
]


def shadow_node(scale):
    """The Shadow sprite node, or "" when the sprite has no shadow."""
    if not scale:
        return ""
    return ('\n[node name="Shadow" type="Sprite2D" parent="."]\n'
            'texture = SubResource("Tex_shadow")\n'
            'modulate = Color(0, 0, 0, 0.58)\n'
            'scale = Vector2(%.2f, %.2f)\n'
            'position = Vector2(0, 2)\n'
            'z_index = -1\n' % scale)


def ref(name):
    return rel("assets", "sprites", "refs", name + ".png")

# Collision layer bits, matching [layer_names] in project.godot.
L_PLAYER, L_ENEMY, L_PBULLET, L_EBULLET = 1, 2, 4, 8
L_ENV, L_WALL, L_GRAZE, L_DOOR = 16, 32, 64, 128


def rel(*parts):
    return "res://" + "/".join(parts)


def encode_tile_map_data(cells):
    """
    Encode cells into the PackedByteArray that TileMapLayer.tile_map_data
    expects.

    This is NOT a PackedInt32Array. Getting that wrong is silent in the
    scene file and loud at runtime:

        set_tile_map_data_from_array: Unsupported tile map data format: 257

    The real layout, from Godot's TileMapLayer::set_tile_map_data_from_array:

        bytes 0-1     uint16 format version, currently 0
        then, 12 bytes per cell, little-endian:
          0-1   int16   cell x
          2-3   int16   cell y
          4-5   uint16  source id   (which TileSet source)
          6-7   int16   atlas coords x
          8-9   int16   atlas coords y
          10-11 uint16  alternative tile id

    `cells` is a list of (x, y, source_id, atlas_x, atlas_y, alternative).
    """
    import struct
    out = bytearray()
    out += struct.pack("<H", 0)                     # format version
    for x, y, source_id, ax, ay, alt in cells:
        out += struct.pack("<hhHhhH", x, y, source_id, ax, ay, alt)
    return "PackedByteArray(%s)" % ", ".join(str(b) for b in out)


def sprite_frames_block(sub_id, ext_ids, speed=5.0):
    """A SpriteFrames sub-resource with one looping animation per direction."""
    anims = []
    for d in DIRECTIONS:
        anims.append(
            '{\n'
            '"frames": [{\n'
            '"duration": 1.0,\n'
            '"texture": ExtResource("%s")\n'
            '}],\n'
            '"loop": true,\n'
            '"name": &"idle_%s",\n'
            '"speed": %.1f\n'
            '}' % (ext_ids[d], d, speed)
        )
    return (
        '[sub_resource type="SpriteFrames" id="%s"]\n'
        'animations = [%s]\n' % (sub_id, ", ".join(anims))
    )


def write(name, text):
    os.makedirs(SCENES, exist_ok=True)
    path = os.path.join(SCENES, name)
    with open(path, "w") as fh:
        fh.write(text)
    print("[scenes]", os.path.relpath(path, ROOT))


# --------------------------------------------------------------------------
# Player.tscn
# --------------------------------------------------------------------------

def make_player():
    ext = []
    ext_ids = {}
    ext.append('[ext_resource type="Script" '
               'path="res://scripts/Player.gd" id="s_player"]')
    ext.append('[ext_resource type="Script" '
               'path="res://scripts/GrazeMeter.gd" id="s_graze"]')
    ext.append('[ext_resource type="Script" '
               'path="res://scripts/Shockwave.gd" id="s_shock"]')
    if SPRITE_SET == "refs":
        ext.append('[ext_resource type="Texture2D" path="%s" id="t_ref"]'
                   % ref("hero"))
        ext_ids = {d: "t_ref" for d in DIRECTIONS}
        off_y = REF_SPRITES["hero"]["offset_y"]
        shadow = shadow_node(REF_SPRITES["hero"]["shadow"])
    else:
        for i, d in enumerate(DIRECTIONS):
            rid = "t_%s" % d
            ext_ids[d] = rid
            ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]'
                       % (rel("assets", "sprites", "player",
                              "player_idle_%s.png" % d), rid))
        off_y = PLAYER_SPRITE_OFFSET_Y
        shadow = shadow_node((0.9, 0.3))

    subs = SHADOW_SUBS + [
        sprite_frames_block("SF_player", ext_ids),
        '[sub_resource type="CircleShape2D" id="Sh_hit"]\n'
        'radius = %d.0\n' % PLAYER_HITBOX_RADIUS,
        # The graze ring is the hitbox radius plus the GDD's 20 px, so the
        # Area2D's edge is exactly the graze threshold. Daryl's detection can
        # then use area_entered rather than measuring distances every frame.
        '[sub_resource type="CircleShape2D" id="Sh_graze"]\n'
        'radius = %d.0\n' % (PLAYER_HITBOX_RADIUS + GRAZE_DISTANCE_PX),
    ]

    body = '''
[node name="Player" type="CharacterBody2D"]
collision_layer = {L_PLAYER}
collision_mask = {wall_env}
script = ExtResource("s_player")
{shadow}
[node name="Sprite" type="AnimatedSprite2D" parent="."]
sprite_frames = SubResource("SF_player")
animation = &"idle_SE"
offset = Vector2(0, {off_y})

[node name="Hitbox" type="CollisionShape2D" parent="."]
shape = SubResource("Sh_hit")

[node name="Muzzle" type="Marker2D" parent="."]
position = Vector2(10, -14)

[node name="GrazeArea" type="Area2D" parent="."]
collision_layer = {L_GRAZE}
collision_mask = {L_EBULLET}
monitorable = false

[node name="Shape" type="CollisionShape2D" parent="GrazeArea"]
shape = SubResource("Sh_graze")

[node name="GrazeMeter" type="Node2D" parent="."]
script = ExtResource("s_graze")

[node name="Shockwave" type="Node2D" parent="."]
script = ExtResource("s_shock")

[node name="Ring" type="Line2D" parent="Shockwave"]
visible = false
width = 3.0
default_color = Color(1, 0.788235, 0.235294, 1)

[node name="Camera" type="Camera2D" parent="."]
position_smoothing_enabled = true
position_smoothing_speed = 8.0
limit_left = 0
limit_top = 0
limit_right = 1152
limit_bottom = 640
'''.format(L_PLAYER=L_PLAYER, L_GRAZE=L_GRAZE, L_EBULLET=L_EBULLET,
           wall_env=L_WALL | L_ENV, off_y=off_y, shadow=shadow)

    steps = len(ext) + len(subs) + 1
    write("Player.tscn",
          '[gd_scene load_steps=%d format=3]\n\n' % steps
          + "\n".join(ext) + "\n\n" + "\n".join(subs) + body)


# --------------------------------------------------------------------------
# Enemy.tscn - one scene, tier set by the exported `enemy_type`
# --------------------------------------------------------------------------

def make_enemy():
    """
    One Enemy.tscn covers all three tiers.

    The alternative - three scenes - would triple the places Jarman has to
    edit when the AI changes. Instead the tier is an exported field, and
    RoomManager sets it when spawning. Each tier's SpriteFrames is present in
    the scene, and _ready picks the right one.
    """
    ext = ['[ext_resource type="Script" '
           'path="res://scripts/Enemy.gd" id="s_enemy"]']
    subs = list(SHADOW_SUBS)
    meta = []
    for tier in ("snail", "hare", "grotesque", "scribe"):
        ids = {}
        if SPRITE_SET == "refs":
            rid = "t_%s" % tier
            ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]'
                       % (ref(tier), rid))
            ids = {d: rid for d in DIRECTIONS}
            off_y = REF_SPRITES[tier]["offset_y"]
            shadow = REF_SPRITES[tier]["shadow"]
        else:
            for d in DIRECTIONS:
                rid = "t_%s_%s" % (tier, d)
                ids[d] = rid
                ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]'
                           % (rel("assets", "sprites", "enemy",
                                  "enemy_%s_idle_%s.png" % (tier, d)), rid))
            off_y = ENEMY_SPRITE_OFFSET_Y[tier]
            shadow = (1.2, 0.4)
        subs.append(sprite_frames_block("SF_%s" % tier, ids))
        # One hitbox per species; shapes are shared resources, so sizing
        # them at runtime would resize every enemy at once.
        subs.append('[sub_resource type="CircleShape2D" id="Sh_%s"]\n'
                    'radius = %d.0\n' % (tier, ENEMY_HITBOX_RADIUS[tier]))
        meta.append('metadata/frames_%s = SubResource("SF_%s")' % (tier, tier))
        meta.append('metadata/hitbox_%s = SubResource("Sh_%s")' % (tier, tier))
        meta.append('metadata/offset_%s = %.1f' % (tier, off_y))
        meta.append('metadata/shadow_%s = Vector2(%.2f, %.2f)' % ((tier,) + shadow))

    subs.append('[sub_resource type="CircleShape2D" id="Sh_enemy"]\n'
                'radius = %d.0\n' % ENEMY_HITBOX_RADIUS["snail"])
    first_off = (REF_SPRITES["snail"]["offset_y"] if SPRITE_SET == "refs"
                 else ENEMY_SPRITE_OFFSET_Y["snail"])
    first_shadow = (REF_SPRITES["snail"]["shadow"] if SPRITE_SET == "refs"
                    else (1.2, 0.4))

    body = '''
[node name="Enemy" type="CharacterBody2D"]
collision_layer = {L_ENEMY}
collision_mask = {mask}
script = ExtResource("s_enemy")
species = "snail"
{meta}
{shadow}
[node name="Sprite" type="AnimatedSprite2D" parent="."]
sprite_frames = SubResource("SF_snail")
animation = &"idle_SE"
offset = Vector2(0, {off_y})

[node name="Hitbox" type="CollisionShape2D" parent="."]
shape = SubResource("Sh_enemy")


[node name="Agent" type="NavigationAgent2D" parent="."]
radius = 14.0
path_desired_distance = 8.0
target_desired_distance = 8.0
avoidance_enabled = true
'''.format(L_ENEMY=L_ENEMY, mask=L_WALL | L_ENV | L_PLAYER,
           off_y=first_off, meta="\n".join(meta),
           shadow=shadow_node(first_shadow))

    steps = len(ext) + len(subs) + 1
    write("Enemy.tscn",
          '[gd_scene load_steps=%d format=3]\n\n' % steps
          + "\n".join(ext) + "\n\n" + "\n".join(subs) + body)


# --------------------------------------------------------------------------
# Bullets
# --------------------------------------------------------------------------

def make_bullets():
    write("EnemyBullet.tscn", '''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/EnemyBullet.gd" id="s_b"]
[ext_resource type="Texture2D" path="{tex}" id="t_b"]

[sub_resource type="CircleShape2D" id="Sh_b"]
radius = {r}.0

[node name="EnemyBullet" type="Area2D"]
collision_layer = {layer}
collision_mask = {mask}
script = ExtResource("s_b")

[node name="Sprite" type="Sprite2D" parent="."]
texture = ExtResource("t_b")

[node name="Shape" type="CollisionShape2D" parent="."]
shape = SubResource("Sh_b")

[connection signal="body_entered" from="." to="." method="_on_body_entered"]
'''.format(tex=rel("assets", "sprites", "props", "bullet_enemy.png"),
           r=ENEMY_BULLET_RADIUS, layer=L_EBULLET,
           mask=L_PLAYER | L_WALL | L_ENV))

    write("PlayerBullet.tscn", '''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/PlayerBullet.gd" id="s_b"]
[ext_resource type="Texture2D" path="{tex}" id="t_b"]

[sub_resource type="CircleShape2D" id="Sh_b"]
radius = {r}.0

[node name="PlayerBullet" type="Area2D"]
collision_layer = {layer}
collision_mask = {mask}
script = ExtResource("s_b")

[node name="Sprite" type="Sprite2D" parent="."]
texture = ExtResource("t_b")

[node name="Shape" type="CollisionShape2D" parent="."]
shape = SubResource("Sh_b")
'''.format(tex=rel("assets", "sprites", "props", "bullet_player.png"),
           r=PLAYER_BULLET_RADIUS, layer=L_PBULLET,
           mask=L_ENEMY | L_WALL | L_ENV))


# --------------------------------------------------------------------------
# Environmental objects
# --------------------------------------------------------------------------

def make_env_objects():
    """
    Barrel, Cover and Trap share EnvObject.gd and differ by `kind` plus the
    textures they carry as metadata. EnvObject._refresh_visual() looks the
    textures up by name, so the script never hard-codes an asset path and
    adding a damage stage is a scene edit, not a code edit.
    """
    def scene(name, kind_value, shape, textures, layer, mask, extra="",
              look=None):
        ext = ['[ext_resource type="Script" '
               'path="res://scripts/EnvObject.gd" id="s_env"]']
        meta = []
        for i, (key, path) in enumerate(textures):
            rid = "t_%d" % i
            ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]'
                       % (path, rid))
            meta.append('metadata/%s = ExtResource("%s")' % (key, rid))
        look = look or {"offset_y": 0, "shadow": None}
        subs = (SHADOW_SUBS if look["shadow"] else []) + [shape]
        steps = len(ext) + len(subs) + 1
        return ('[gd_scene load_steps=%d format=3]\n\n' % steps
                + "\n".join(ext) + "\n\n" + "\n".join(subs)
                + '\n[node name="%s" type="StaticBody2D"]\n'
                  'collision_layer = %d\ncollision_mask = %d\n'
                  'script = ExtResource("s_env")\nkind = %d\n'
                  % (name, layer, mask, kind_value)
                + shadow_node(look["shadow"])
                + '\n[node name="Sprite" type="Sprite2D" parent="."]\n'
                + 'texture = ExtResource("t_0")\n'
                + 'offset = Vector2(0, %d)\n' % look["offset_y"]
                + "\n".join(meta) + "\n"
                + '\n[node name="Shape" type="CollisionShape2D" parent="."]\n'
                  'shape = SubResource("Sh")\n'
                + extra)

    p = lambda n: rel("assets", "sprites", "props", n)
    use_refs = SPRITE_SET == "refs"

    write("Barrel.tscn", scene(
        "Barrel", 0,
        '[sub_resource type="CircleShape2D" id="Sh"]\nradius = 11.0\n',  # flask base ~24 px across
        [("texture_barrel", ref("lamp_oil") if use_refs else p("barrel.png"))],
        L_ENV, L_PLAYER | L_ENEMY | L_PBULLET | L_EBULLET,
        look=REF_SPRITES["lamp_oil"] if use_refs else None))

    write("Cover.tscn", scene(
        "Cover", 1,
        '[sub_resource type="RectangleShape2D" id="Sh"]\n'
        'size = Vector2(46, 30)\n',   # tome stack footprint
        [("texture_intact", ref("tome_1") if use_refs else p("cover_intact.png")),
         ("texture_cracked", ref("tome_2") if use_refs else p("cover_cracked.png")),
         ("texture_crumbling", ref("tome_3") if use_refs else p("cover_crumbling.png"))],
        L_ENV, L_PLAYER | L_ENEMY | L_PBULLET | L_EBULLET,
        look=REF_SPRITES["tome"] if use_refs else None))

    # A trap is walked ONTO, not collided with, so its root sits on NO
    # physics layer - otherwise the player and every enemy would be stopped
    # dead by a flat floor plate. Detection is the child Area2D instead.
    # The root stays a StaticBody2D so one script still covers all three
    # kinds; EnvObject._ready() puts it in the "env_object" and "hazard"
    # groups, which is how other systems find it, so it loses nothing by
    # being off the physics layers.
    write("Trap.tscn", scene(
        "Trap", 2,
        '[sub_resource type="RectangleShape2D" id="Sh"]\n'
        'size = Vector2(66, 44)\n',   # trap plate, foreshortened on Y
        # On the prop sheet the plate with short spikes is the retracted one,
        # the tall clean spikes are armed, the bloodied spikes are triggered.
        [("texture_armed", ref("trap_2") if use_refs else p("trap_armed.png")),
         ("texture_disarmed", ref("trap_1") if use_refs else p("trap_disarmed.png")),
         ("texture_triggered", ref("trap_3") if use_refs else p("trap_triggered.png"))],
        0, 0,
        look=REF_SPRITES["trap"] if use_refs else None,
        extra='\n[node name="Trigger" type="Area2D" parent="."]\n'
              'collision_layer = 0\ncollision_mask = %d\n'
              '\n[node name="Shape" type="CollisionShape2D" parent="Trigger"]\n'
              'shape = SubResource("Sh")\n'
              '\n[connection signal="body_entered" from="Trigger" to="." '
              'method="_on_body_entered"]\n' % (L_PLAYER | L_ENEMY)))


def make_fixture():
    """
    Fixture.tscn - a fixed tome wall. Layouts place these to shape a room:
    lanes, pillars, a horseshoe. They sit on the WALL layer, never break,
    and the navigation bake treats them as walls, which is what the GDD's
    "routes around walls" needs something to route around.
    """
    tex = ref("tome_1") if SPRITE_SET == "refs" else rel("assets", "sprites", "props", "cover_intact.png")
    subs = SHADOW_SUBS + ['[sub_resource type="RectangleShape2D" id="Sh"]\nsize = Vector2(46, 30)\n']
    write("Fixture.tscn", '[gd_scene load_steps=%d format=3]\n\n' % (1 + len(subs) + 1)
          + '[ext_resource type="Texture2D" path="%s" id="t_0"]\n\n' % tex
          + "\n".join(subs)
          + '\n[node name="Fixture" type="StaticBody2D" groups=["fixture"]]\n'
            'collision_layer = %d\ncollision_mask = 0\n' % L_WALL
          + shadow_node(REF_SPRITES["tome"]["shadow"])
          + '\n[node name="Sprite" type="Sprite2D" parent="."]\n'
            'texture = ExtResource("t_0")\n'
            'offset = Vector2(0, %d)\n' % REF_SPRITES["tome"]["offset_y"]
          + 'modulate = Color(0.78, 0.76, 0.86, 1)\n'
          + '\n[node name="Shape" type="CollisionShape2D" parent="."]\n'
            'shape = SubResource("Sh")\n')


def make_powerup():
    """
    PowerUp.tscn - the Luminous Pigment Shell.

    GDD, Combat Rewards: dropped every 5th enemy defeated, grants +20% weapon
    damage for 10 s, does not stack, a new pickup resets the timer.

    An Area2D rather than a body: the player walks over it, they do not bump
    into it.
    """
    write("PowerUp.tscn", '''[gd_scene load_steps=4 format=3]

[ext_resource type="Script" path="res://scripts/PowerUp.gd" id="s_pu"]
[ext_resource type="Texture2D" path="{tex}" id="t_pu"]

[sub_resource type="CircleShape2D" id="Sh_pu"]
radius = 16.0

[node name="PowerUp" type="Area2D"]
collision_layer = 0
collision_mask = {mask}
script = ExtResource("s_pu")

[node name="Sprite" type="Sprite2D" parent="."]
texture = ExtResource("t_pu")
offset = Vector2(0, {off_y})

[node name="Shape" type="CollisionShape2D" parent="."]
shape = SubResource("Sh_pu")

[connection signal="body_entered" from="." to="." method="_on_body_entered"]
'''.format(tex=(ref("shell") if SPRITE_SET == "refs"
                else rel("assets", "sprites", "props", "powerup_shell.png")),
           off_y=REF_SPRITES["shell"]["offset_y"] if SPRITE_SET == "refs" else 0,
           mask=L_PLAYER))


# --------------------------------------------------------------------------
# TileSet and Room
# --------------------------------------------------------------------------

def make_tileset():
    """
    One atlas source per tile PNG.

    The tiles are rendered as separate files rather than packed into one
    atlas image, because packing would need an image library the pipeline
    does not have and gains nothing at this tile count.
    """
    ext, sources, entries = [], [], []
    tiles = [("floor_0", 0), ("floor_1", 1), ("floor_2", 2), ("floor_3", 3),
             ("wall", 4)]
    for name, idx in tiles:
        rid = "t_%s" % name
        ext.append('[ext_resource type="Texture2D" path="%s" id="%s"]'
                   % (rel("assets", "sprites", "tiles", "%s.png" % name), rid))
        # Walls render in a 128 px frame (two tiles tall) so the block's
        # height is not cropped; floors are exactly one 64 px tile.
        # Every tile, walls included, is exactly one 64 x 64 cell. A
        # taller region would make walls span two map cells.
        region = "Vector2i(64, 64)"
        src = ('[sub_resource type="TileSetAtlasSource" id="A_%s"]\n'
               'texture = ExtResource("%s")\n'
               'texture_region_size = %s\n'
               '0:0/0 = 0\n' % (name, rid, region))
        # Walls block movement and bullets, so they get a physics polygon.
        if name == "wall":
            # Tile-local coordinates are centred on the cell, so a 64 x 64
            # tile spans -32..32 on BOTH axes. Using 0..64 for y, as an
            # earlier pass did, drops every wall's collision half a tile
            # below the wall you can see.
            src += ('0:0/0/physics_layer_0/polygon_0/points = '
                    'PackedVector2Array(-32, -32, 32, -32, 32, 32, '
                    '-32, 32)\n')
        sources.append(src)
        entries.append('sources/%d = SubResource("A_%s")' % (idx, name))

    steps = len(ext) + len(sources) + 1
    # tile_size is NOT optional. Leave it out and TileSet silently falls
    # back to 16 x 16, so 64 px art gets laid out on a 16 px grid and the
    # room renders as a quarter-size smear in the corner.
    body = ('\n[resource]\n'
            'tile_size = Vector2i(64, 64)\n'
            'physics_layer_0/collision_layer = %d\n' % L_WALL
            + "\n".join(entries) + "\n")
    path = os.path.join(ROOT, "assets", "RoomTileSet.tres")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write('[gd_resource type="TileSet" load_steps=%d format=3]\n\n'
                 % steps
                 + "\n".join(ext) + "\n\n" + "\n".join(sources) + body)
    print("[scenes]", os.path.relpath(path, ROOT))


def make_room():
    """
    Room.tscn - a painted background plus collision, not a tilemap.

    The reference room is a diorama: a floor quadrilateral with three walls
    standing around it and ornament concentrated on the walls. A 64 px square
    tile grid cannot express that, so the room is rendered as one image by
    pipeline/room.py, which also exports room_01.json - the floor outline,
    door anchors and marker positions, all in PIXELS, projected through the
    real camera.

    Reading that file rather than hard-coding coordinates means the engine
    and the art cannot drift apart: change the room's size or the camera
    angle, re-render, and the collision follows.
    """
    layout_path = os.path.join(ROOT, "assets", "sprites", "rooms",
                               "room_01.json")
    if not os.path.exists(layout_path):
        print("[scenes] SKIP Room.tscn - run: blender -b --python "
              "pipeline/room.py")
        return

    import json
    with open(layout_path) as fh:
        L = json.load(fh)

    poly = L["floor_polygon"]
    poly_str = ", ".join("%.1f, %.1f" % (p[0], p[1]) for p in poly)

    xs = [p[0] for p in poly]
    ys = [p[1] for p in poly]
    centre = ((min(xs) + max(xs)) * 0.5, (min(ys) + max(ys)) * 0.5)

    nodes = []
    for name, pos in L["doors"].items():
        nodes.append('[node name="Door%s" type="Marker2D" parent="Doors"]\n'
                     'position = Vector2(%.1f, %.1f)\n'
                     % (name.capitalize(), pos[0], pos[1]))
    for i, pos in enumerate(L["spawn_markers"]):
        nodes.append('[node name="Spawn%d" type="Marker2D" '
                     'parent="SpawnMarkers"]\nposition = Vector2(%.1f, %.1f)\n'
                     % (i, pos[0], pos[1]))
    for i, pos in enumerate(L["object_markers"]):
        nodes.append('[node name="ObjSpot%d" type="Marker2D" '
                     'parent="ObjectMarkers"]\nposition = Vector2(%.1f, %.1f)\n'
                     % (i, pos[0], pos[1]))

    write("Room.tscn", '''[gd_scene load_steps=3 format=3]

[ext_resource type="Script" path="res://scripts/RoomManager.gd" id="s_room"]
[ext_resource type="Texture2D" path="{img}" id="t_bg"]

[node name="Room" type="Node2D"]
script = ExtResource("s_room")
metadata/floor_centre = Vector2({cx:.1f}, {cy:.1f})

[node name="Background" type="Sprite2D" parent="."]
texture = ExtResource("t_bg")
centered = false
z_index = -10

[node name="Bounds" type="StaticBody2D" parent="."]
collision_layer = {wall}
collision_mask = 0

[node name="Shape" type="CollisionPolygon2D" parent="Bounds"]
build_mode = 1
polygon = PackedVector2Array({poly})

[node name="NavRegion" type="NavigationRegion2D" parent="."]

[node name="Doors" type="Node2D" parent="."]

[node name="SpawnMarkers" type="Node2D" parent="."]

[node name="ObjectMarkers" type="Node2D" parent="."]

[node name="Enemies" type="Node2D" parent="."]
y_sort_enabled = true

[node name="Objects" type="Node2D" parent="."]
y_sort_enabled = true

{nodes}
'''.format(img=rel("assets", "sprites", "rooms", L["image"]),
           cx=centre[0], cy=centre[1], wall=L_WALL,
           poly=poly_str, nodes="\n".join(nodes)))

    # Main.tscn needs the player to start standing on the floor.
    global PLAYER_START
    PLAYER_START = centre


PLAYER_START = (576.0, 320.0)


# --------------------------------------------------------------------------
# HUD and Main
# --------------------------------------------------------------------------

def make_hud():
    """
    The HUD, pinned to the screen edges.

    Nothing sits in the middle: the avoid list bans anything that hides
    bullets or the player hitbox, and in a bullet hell the centre of the
    screen is where the player is looking.

      top-left      HP bar, and the damage-boost timer under it
      top-right     room counter
      bottom-centre Graze Meter, with the Shockwave prompt above it
    """
    def bar_style(sid, colour, bg=False):
        return ('[sub_resource type="StyleBoxFlat" id="%s"]\n'
                'bg_color = %s\n'
                'corner_radius_top_left = 2\ncorner_radius_top_right = 2\n'
                'corner_radius_bottom_right = 2\n'
                'corner_radius_bottom_left = 2\n'
                % (sid, colour)
                + ('border_width_left = 2\nborder_width_top = 2\n'
                   'border_width_right = 2\nborder_width_bottom = 2\n'
                   'border_color = Color(0.070588, 0.054902, 0.101961, 1)\n'
                   if bg else ''))

    ABYSS = "Color(0.070588, 0.054902, 0.101961, 0.85)"
    EMBER = "Color(0.941176, 0.415686, 0.164706, 1)"
    GOLD = "Color(1, 0.788235, 0.235294, 1)"
    TEAL = "Color(0.207843, 0.839216, 0.768627, 1)"
    BONE = "Color(0.847059, 0.784314, 0.658824, 1)"

    subs = (bar_style("Sb_bg", ABYSS, bg=True)
            + bar_style("Sb_hp", EMBER)
            + bar_style("Sb_meter", GOLD)
            + bar_style("Sb_boost", TEAL)
            + '[sub_resource type="StyleBoxFlat" id="Sb_panel"]\n'
              'bg_color = Color(0.070588, 0.054902, 0.101961, 0.94)\n'
              'border_width_left = 3\nborder_width_top = 3\n'
              'border_width_right = 3\nborder_width_bottom = 3\n'
              'border_color = %s\n'
              'corner_radius_top_left = 4\ncorner_radius_top_right = 4\n'
              'corner_radius_bottom_right = 4\n'
              'corner_radius_bottom_left = 4\n' % BONE)

    write("HUD.tscn", '''[gd_scene load_steps=7 format=3]

[ext_resource type="Script" path="res://scripts/HUD.gd" id="s_hud"]

{subs}
[node name="HUD" type="CanvasLayer"]
script = ExtResource("s_hud")

[node name="Root" type="Control" parent="."]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 2

[node name="TopLeft" type="VBoxContainer" parent="Root"]
offset_left = 24.0
offset_top = 20.0
offset_right = 324.0
offset_bottom = 92.0
theme_override_constants/separation = 6

[node name="HPBar" type="ProgressBar" parent="Root/TopLeft"]
custom_minimum_size = Vector2(300, 26)
max_value = 100.0
value = 100.0
show_percentage = false
theme_override_styles/background = SubResource("Sb_bg")
theme_override_styles/fill = SubResource("Sb_hp")

[node name="HPLabel" type="Label" parent="Root/TopLeft/HPBar"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
text = "100 / 100"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_colors/font_color = {BONE}
theme_override_font_sizes/font_size = 14

[node name="BoostBar" type="ProgressBar" parent="Root/TopLeft"]
visible = false
custom_minimum_size = Vector2(220, 16)
max_value = 10.0
value = 0.0
show_percentage = false
theme_override_styles/background = SubResource("Sb_bg")
theme_override_styles/fill = SubResource("Sb_boost")

[node name="BoostLabel" type="Label" parent="Root/TopLeft/BoostBar"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
text = "+20%  10.0s"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_colors/font_color = {BONE}
theme_override_font_sizes/font_size = 11

[node name="TopRight" type="VBoxContainer" parent="Root"]
anchors_preset = 1
anchor_left = 1.0
anchor_right = 1.0
offset_left = -260.0
offset_top = 20.0
offset_right = -24.0
offset_bottom = 52.0
alignment = 2

[node name="RoomLabel" type="Label" parent="Root/TopRight"]
text = "ROOM  1 / 8"
horizontal_alignment = 2
theme_override_colors/font_color = {BONE}
theme_override_font_sizes/font_size = 18

[node name="BottomCentre" type="VBoxContainer" parent="Root"]
anchors_preset = 7
anchor_left = 0.5
anchor_top = 1.0
anchor_right = 0.5
anchor_bottom = 1.0
offset_left = -210.0
offset_top = -78.0
offset_right = 210.0
offset_bottom = -22.0
theme_override_constants/separation = 6

[node name="ShockwaveHint" type="Label" parent="Root/BottomCentre"]
visible = false
text = "SHOCKWAVE READY  -  press Q"
horizontal_alignment = 1
theme_override_colors/font_color = {GOLD}
theme_override_font_sizes/font_size = 15

[node name="MeterBar" type="ProgressBar" parent="Root/BottomCentre"]
custom_minimum_size = Vector2(420, 22)
max_value = 100.0
value = 0.0
show_percentage = false
theme_override_styles/background = SubResource("Sb_bg")
theme_override_styles/fill = SubResource("Sb_meter")

[node name="MeterLabel" type="Label" parent="Root/BottomCentre/MeterBar"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
text = "GRAZE  0 / 100"
horizontal_alignment = 1
vertical_alignment = 1
theme_override_colors/font_color = {BONE}
theme_override_font_sizes/font_size = 13

[node name="EndScreen" type="Control" parent="Root"]
visible = false
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
mouse_filter = 0

[node name="Panel" type="PanelContainer" parent="Root/EndScreen"]
anchors_preset = 8
anchor_left = 0.5
anchor_top = 0.5
anchor_right = 0.5
anchor_bottom = 0.5
offset_left = -220.0
offset_top = -110.0
offset_right = 220.0
offset_bottom = 110.0
theme_override_styles/panel = SubResource("Sb_panel")

[node name="VBox" type="VBoxContainer" parent="Root/EndScreen/Panel"]
theme_override_constants/separation = 18

[node name="Title" type="Label" parent="Root/EndScreen/Panel/VBox"]
text = "RUN OVER"
horizontal_alignment = 1
theme_override_colors/font_color = {GOLD}
theme_override_font_sizes/font_size = 34

[node name="Subtitle" type="Label" parent="Root/EndScreen/Panel/VBox"]
text = "Restarting at room 1 with new layouts."
horizontal_alignment = 1
autowrap_mode = 2
theme_override_colors/font_color = {BONE}
theme_override_font_sizes/font_size = 15

[node name="RestartButton" type="Button" parent="Root/EndScreen/Panel/VBox"]
custom_minimum_size = Vector2(0, 44)
text = "RUN AGAIN"
'''.format(subs=subs, BONE=BONE, GOLD=GOLD))


def make_main():
    write("Main.tscn", '''[gd_scene load_steps=5 format=3]

[ext_resource type="Script" path="res://scripts/GameManager.gd" id="s_gm"]
[ext_resource type="PackedScene" path="res://scenes/Room.tscn" id="sc_room"]
[ext_resource type="PackedScene" path="res://scenes/Player.tscn" id="sc_player"]
[ext_resource type="PackedScene" path="res://scenes/HUD.tscn" id="sc_hud"]

[node name="Main" type="Node2D"]
y_sort_enabled = true
script = ExtResource("s_gm")

[node name="Room" parent="." instance=ExtResource("sc_room")]

[node name="Player" parent="." instance=ExtResource("sc_player")]
position = Vector2({px:.1f}, {py:.1f})

[node name="HUD" parent="." instance=ExtResource("sc_hud")]
'''.format(px=PLAYER_START[0], py=PLAYER_START[1]))


def main():
    make_player()
    make_enemy()
    make_bullets()
    make_env_objects()
    make_fixture()
    make_powerup()
    # make_tileset() - retired: rooms are painted backgrounds now.
    make_room()
    make_hud()
    make_main()
    print("\nScenes generated. Open project.godot in Godot 4.4+.")


if __name__ == "__main__":
    main()
