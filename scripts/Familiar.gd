extends Node2D
## The Inkling: a small ink imp that trails the knight and shoots the nearest
## enemy in range. Isaac's familiars, Gungeon's companions. NOT IN THE GDD.
##
## Its shots are plain PlayerBullets at FAMILIAR_DAMAGE: the knight's
## equipment does not apply to them, so it stays a helper, not a second gun.

const PLAYER_BULLET_SCENE: PackedScene = preload("res://scenes/PlayerBullet.tscn")
const FOLLOW_OFFSET := Vector2(-34, -26)

var owner_player: Player
var _cooldown: float = 0.6
var _t: float = 0.0
var _sprite: Sprite2D


func _ready() -> void:
	add_to_group("familiar")
	z_index = 5
	_sprite = Sprite2D.new()
	var tex_path := Items.ICON_DIR + "inkling_familiar.png"
	_sprite.texture = load(tex_path) if ResourceLoader.exists(tex_path) else Items.hud_icon("inkling")
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_sprite)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(owner_player) or owner_player.is_dead:
		return
	_t += delta
	# Lag behind the knight on the side away from where he aims.
	var side := FOLLOW_OFFSET
	if owner_player.aim_direction.x < 0.0:
		side.x = -side.x
	var want := owner_player.global_position + side + Vector2(0, sin(_t * 3.0) * 4.0)
	global_position = global_position.lerp(want, minf(1.0, delta * 6.0))

	_cooldown -= delta
	if _cooldown > 0.0:
		return
	var target := _nearest_enemy()
	if target == null:
		return
	_cooldown = Items.FAMILIAR_FIRE_INTERVAL
	var dir := (target.global_position + Vector2(0, -10) - global_position).normalized()
	var b := PLAYER_BULLET_SCENE.instantiate() as PlayerBullet
	b.direction = dir
	b.damage = Items.FAMILIAR_DAMAGE
	b.size_scale = 0.7
	b.global_position = global_position
	get_tree().current_scene.add_child(b)
	var tw := create_tween()
	tw.tween_property(_sprite, "scale", Vector2(1.2, 0.85), 0.05)
	tw.tween_property(_sprite, "scale", Vector2.ONE, 0.1)


func _nearest_enemy() -> Node2D:
	var best: Node2D = null
	var best_d := Items.FAMILIAR_RANGE_PX
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Enemy) or (e as Enemy).hp <= 0:
			continue
		var d := global_position.distance_to((e as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best
