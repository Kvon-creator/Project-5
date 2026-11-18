class_name ItemPickup
extends Area2D
## An item on the floor. Walk over it to take it. NOT IN THE GDD.
##
## Built entirely in code, so there is no scene for pipeline/make_scenes.py
## to regenerate over. Make one with ItemPickup.make(id).
##
## Pickups offered together (the room-clear choice) share a `group_id`:
## taking one makes the others crumble, the way a room in Hades offers one
## boon from several.

signal taken(id: String)

const BOB_PIXELS := 4.0
const BOB_SECONDS := 1.4

var item_id: String = ""
var group_id: int = 0
var _taken: bool = false
var _sprite: Sprite2D
var _label: Label


static func make(id: String) -> ItemPickup:
	var p := ItemPickup.new()
	p.item_id = id
	return p


func _ready() -> void:
	add_to_group("item_pickup")
	collision_layer = 0
	collision_mask = 1          # the player
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 18.0
	shape.shape = circle
	add_child(shape)

	var shadow := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 16:
		var a := TAU * i / 16.0
		pts.append(Vector2(cos(a) * 16.0, sin(a) * 5.0))
	shadow.polygon = pts
	shadow.color = Color(0, 0, 0, 0.45)
	add_child(shadow)

	_sprite = Sprite2D.new()
	_sprite.texture = Items.icon(item_id)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_sprite.offset = Vector2(0, -26)
	var small := Items.kind(item_id) == Items.Kind.CONSUMABLE
	_sprite.scale = Vector2.ONE * (0.6 if small else 0.75)
	add_child(_sprite)

	# The name floats above it, so the room-clear choice can be read before
	# walking onto one. Equipment only: a heart needs no caption.
	if not small:
		_label = Label.new()
		_label.text = Items.display_name(item_id)
		_label.add_theme_color_override("font_color", Items.kind_colour(item_id).lerp(Palette.PARCHMENT, 0.5))
		_label.add_theme_color_override("font_outline_color", Palette.INK)
		_label.add_theme_constant_override("outline_size", 4)
		_label.add_theme_font_size_override("font_size", 12)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.size = Vector2(140, 18)
		_label.position = Vector2(-70, -72)
		add_child(_label)

	z_index = 2
	body_entered.connect(_on_body_entered)
	# Appear with a pop, then bob.
	_sprite.scale *= 0.2
	var grow := create_tween()
	grow.tween_property(_sprite, "scale", Vector2.ONE * (0.6 if small else 0.75), 0.25) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bob := create_tween().set_loops()
	bob.tween_property(_sprite, "offset:y", -26.0 - BOB_PIXELS, BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)
	bob.tween_property(_sprite, "offset:y", -26.0, BOB_SECONDS * 0.5).set_trans(Tween.TRANS_SINE)


func _on_body_entered(body: Node2D) -> void:
	if _taken or not (body is Player) or (body as Player).is_dead:
		return
	var loadout := (body as Player).loadout
	if loadout == null:
		return
	_taken = true
	loadout.add_item(item_id)
	taken.emit(item_id)
	if group_id != 0:
		for other in get_tree().get_nodes_in_group("item_pickup"):
			if other != self and other is ItemPickup and (other as ItemPickup).group_id == group_id:
				(other as ItemPickup).crumble()
	_play_collect()


## Taken away without being picked: the other half of a choice.
func crumble() -> void:
	if _taken:
		return
	_taken = true
	set_deferred("monitoring", false)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "modulate", Color(Palette.INK, 0.0), 0.35)
	t.tween_property(_sprite, "scale", _sprite.scale * 0.6, 0.35)
	t.chain().tween_callback(queue_free)


func _play_collect() -> void:
	set_deferred("monitoring", false)
	if _label:
		_label.visible = false
	var t := create_tween().set_parallel(true)
	t.tween_property(_sprite, "scale", _sprite.scale * 1.7, 0.2)
	t.tween_property(_sprite, "modulate", Color(Items.kind_colour(item_id), 0.0), 0.2)
	t.chain().tween_callback(queue_free)
