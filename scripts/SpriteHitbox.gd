class_name SpriteHitbox
extends Area2D
## The damage hitbox: an invisible rectangle around exactly the visible
## pixels of a character's current sprite frame.
##
## Bullets hit this, not the character's body. The body keeps its small
## circle at the feet, which is what walks into walls, cover and traps - in a
## 3/4 view a head-sized collider would stop the knight well short of the
## back wall.
##
## The rectangle is measured from the sprite itself (the opaque bounds of the
## frame texture), so it fits every species, follows the sprite when it
## flips, bobs or squashes, and stays right if the art is redrawn.
##
## Made by Player.gd and Enemy.gd with SpriteHitbox.attach(). On the player it
## also sizes the GrazeArea to the hitbox plus the GDD's 20 px graze band.

## Physics layers (project.godot names them). Bullets look for these.
const PLAYER_LAYER: int = 1 << 8     # layer 9, "player_hitbox"
const ENEMY_LAYER: int = 1 << 9      # layer 10, "enemy_hitbox"

## The character this hitbox belongs to (a Player or an Enemy).
var body: Node2D
var sprite: AnimatedSprite2D
var graze_area: Area2D
var graze_margin: float = 0.0
## Optional: texture path -> the part of that texture that counts, in
## texels. Anything outside it is never hit (the knight's staff).
var keep: Dictionary = {}

var _shape: RectangleShape2D
var _graze_shape: RectangleShape2D

## Opaque bounds per texture, measured once.
static var _bounds_cache: Dictionary = {}


static func attach(owner_body: Node2D, owner_sprite: AnimatedSprite2D, layer: int,
		graze: Area2D = null, margin: float = 0.0, keep_rects: Dictionary = {}) -> SpriteHitbox:
	var h := SpriteHitbox.new()
	h.keep = keep_rects
	h.name = "SpriteHitbox"
	h.body = owner_body
	h.sprite = owner_sprite
	h.collision_layer = layer
	h.graze_area = graze
	h.graze_margin = margin
	owner_body.add_child(h)
	return h


func _ready() -> void:
	collision_mask = 0
	monitoring = false       # it is found, it does not look
	monitorable = true
	_shape = RectangleShape2D.new()
	var cs := CollisionShape2D.new()
	cs.name = "Shape"
	cs.shape = _shape
	add_child(cs)
	if graze_area:
		var gcs := graze_area.get_node_or_null("Shape") as CollisionShape2D
		if gcs:
			_graze_shape = RectangleShape2D.new()
			gcs.shape = _graze_shape
	refresh()


func _physics_process(_delta: float) -> void:
	refresh()


## Fit the rectangle to the sprite as it is drawn this frame.
func refresh() -> void:
	if not is_instance_valid(sprite) or sprite.sprite_frames == null:
		return
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if tex == null:
		return
	var used := opaque_rect(tex)
	if keep.has(tex.resource_path):
		used = used.intersection(keep[tex.resource_path])
	var size := Vector2(tex.get_size())
	# Where the frame's opaque pixels sit in the sprite's own space.
	var top_left := sprite.offset - (size * 0.5 if sprite.centered else Vector2.ZERO)
	var centre := top_left + used.position + used.size * 0.5
	if sprite.flip_h:
		centre.x = 2.0 * sprite.offset.x - centre.x + (0.0 if sprite.centered else size.x)
	if sprite.flip_v:
		centre.y = 2.0 * sprite.offset.y - centre.y + (0.0 if sprite.centered else size.y)
	var s := sprite.scale.abs()
	var half := used.size * 0.5 * s
	var c := sprite.position + centre * s
	_shape.size = half * 2.0
	(get_child(0) as CollisionShape2D).position = c
	if _graze_shape:
		_graze_shape.size = half * 2.0 + Vector2.ONE * graze_margin * 2.0
		(graze_area.get_node("Shape") as CollisionShape2D).position = c


## The global rectangle the hitbox covers right now.
func global_rect() -> Rect2:
	var cs := get_child(0) as CollisionShape2D
	var c := global_transform * cs.position
	return Rect2(c - _shape.size * 0.5, _shape.size)


## The bounding box of a texture's non-transparent pixels, in texels.
static func opaque_rect(tex: Texture2D) -> Rect2:
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_rid())
	if _bounds_cache.has(key):
		return _bounds_cache[key]
	var img := tex.get_image()
	# Headless runs have no renderer to read pixels back from; the source
	# file is there instead.
	if (img == null or img.is_empty()) and tex.resource_path != "":
		img = Image.load_from_file(tex.resource_path)
	var r := Rect2(Vector2.ZERO, Vector2(tex.get_size()))
	if img and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var used := img.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			# The image may be stored at a different size than drawn.
			var k := Vector2(tex.get_size()) / Vector2(img.get_size())
			r = Rect2(Vector2(used.position) * k, Vector2(used.size) * k)
	_bounds_cache[key] = r
	return r
