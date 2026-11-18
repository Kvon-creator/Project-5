class_name PlayerBullet
extends Area2D
## The knight's shot.
##
## PREVIEW(Daryl): the smallest thing that makes shooting work. Flies
## straight, damages the first enemy it touches, chips cover and barrels, and
## dies on walls or after LIFETIME_SECONDS. Player.gd sets `direction` and
## `damage` before adding it to the scene.
##
## Equipment (Items.gd, NOT IN THE GDD) can change a shot. Loadout.decorate()
## sets these fields before the bullet enters the scene; with none of them
## set it is exactly the preview shot above.
##   pierce      passes through this many extra enemies
##   homing      steers toward the nearest enemy
##   bounces     reflects off walls this many times
##   burns       sets the enemy burning (BurnEffect.gd)
##   chains      arcs lightning to one more enemy nearby
##   knockback_px, size_scale   the Leaden Nib
##
## Palette: Nib Teal, per the GDD ("Player shots, nib glow, power-up").
## Ember Ink shots lean toward Ember so the player can see the fire.

const SPEED_PX_PER_SECOND: float = 520.0
const LIFETIME_SECONDS: float = 1.5
const WALL_MASK: int = 32           # the wall layer: room bounds and tome walls
const BURN_SCRIPT := preload("res://scripts/BurnEffect.gd")

var direction: Vector2 = Vector2.RIGHT
var damage: int = 10

var pierce: int = 0
var homing: bool = false
var bounces: int = 0
var burns: bool = false
var chains: bool = false
var knockback_px: float = 0.0
var size_scale: float = 1.0

var _hit: Dictionary = {}           # enemies already struck, by instance id
var _life: float = LIFETIME_SECONDS
var _spent: bool = false

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("player_bullet")
	rotation = direction.angle() + PI * 0.5
	sprite.modulate = Palette.PLAYER_SHOT
	if burns:
		sprite.modulate = Palette.PLAYER_SHOT.lerp(Palette.EMBER, 0.6)
	scale = Vector2.ONE * size_scale
	z_index = 4
	body_entered.connect(_on_body_entered)
	# A bouncing shot has further to go.
	_life = LIFETIME_SECONDS * (1.0 + 0.5 * bounces)


func _physics_process(delta: float) -> void:
	_life -= delta
	if _life <= 0.0:
		queue_free()
		return
	if homing:
		var target := _nearest_enemy(Items.HOMING_RANGE_PX)
		if target:
			var want := (target.global_position + Vector2(0, -10) - global_position).normalized()
			var turn := clampf(direction.angle_to(want), -Items.HOMING_TURN_RAD_PER_S * delta,
					Items.HOMING_TURN_RAD_PER_S * delta)
			direction = direction.rotated(turn)
			rotation = direction.angle() + PI * 0.5
	var step := direction * SPEED_PX_PER_SECOND * delta
	if bounces > 0:
		# Look ahead for a wall so the bounce can use its surface normal; an
		# Area2D's body_entered does not report one.
		var q := PhysicsRayQueryParameters2D.create(global_position, global_position + step * 1.5, WALL_MASK)
		q.collide_with_areas = false
		var hit := get_world_2d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			bounces -= 1
			direction = direction.bounce(hit["normal"]).normalized()
			rotation = direction.angle() + PI * 0.5
			global_position = hit["position"] + hit["normal"] * 3.0
			return
	global_position += step


func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is Enemy:
		var e := body as Enemy
		var id := e.get_instance_id()
		if _hit.has(id):
			return
		_hit[id] = true
		_strike(e)
		if pierce > 0:
			pierce -= 1
			return
	elif body is EnvObject:
		(body as EnvObject).take_hit("player")
	elif bounces > 0:
		return   # the ray in _physics_process handles the bounce
	_spent = true
	queue_free()


func _strike(e: Enemy) -> void:
	if knockback_px > 0.0:
		e.apply_knockback(direction * knockback_px)
	if burns and e.hp > 0:
		var burn := e.get_node_or_null("Burn")
		if burn == null:
			burn = Node.new()
			burn.name = "Burn"
			burn.set_script(BURN_SCRIPT)
			e.add_child(burn)
		burn.call("ignite")
	if chains:
		_chain_from(e)
	e.take_damage(damage, "player")


## Storm Quill: lightning jumps to the nearest other enemy.
func _chain_from(e: Enemy) -> void:
	var best: Enemy = null
	var best_d := Items.CHAIN_RANGE_PX
	for o in get_tree().get_nodes_in_group("enemy"):
		if o == e or not (o is Enemy) or (o as Enemy).hp <= 0:
			continue
		var d := e.global_position.distance_to((o as Enemy).global_position)
		if d < best_d:
			best_d = d
			best = o
	if best == null:
		return
	_draw_bolt(e.global_position + Vector2(0, -12), best.global_position + Vector2(0, -12))
	best.take_damage(maxi(1, int(round(damage * Items.CHAIN_DAMAGE_SCALE))), "player")


func _draw_bolt(a: Vector2, b: Vector2) -> void:
	var bolt := Line2D.new()
	bolt.width = 2.0
	bolt.default_color = Palette.PARCHMENT
	bolt.z_index = 6
	var n := 6
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		if i > 0 and i < n:
			p += (b - a).orthogonal().normalized() * randf_range(-7.0, 7.0)
		bolt.add_point(p)
	get_tree().current_scene.add_child(bolt)
	var t := bolt.create_tween()
	t.tween_property(bolt, "modulate", Color(Palette.NIB_TEAL, 0.0), 0.18)
	t.tween_callback(bolt.queue_free)


func _nearest_enemy(within: float) -> Node2D:
	var best: Node2D = null
	var best_d := within
	for o in get_tree().get_nodes_in_group("enemy"):
		if not (o is Enemy) or (o as Enemy).hp <= 0 or _hit.has(o.get_instance_id()):
			continue
		var d := global_position.distance_to((o as Node2D).global_position)
		if d < best_d:
			best_d = d
			best = o
	return best
