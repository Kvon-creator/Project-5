class_name Shockwave
extends Node2D
## Mechanic 4: Shockwave.
##
## OWNER: Daryl Watkins-Mattocks. Due Nov 18.
## GDD architecture box: "Shockwave.gd / child of Player.tscn / Shockwave:
## ready flag, 1 s invulnerable timer".
## Reads: GrazeMeter, EnemyBullet, Enemy, EnvObject
##        ("Meter = 100; bullets, enemies and barrels in 150 px").
##
## GDD input: "Q, only when the Graze Meter is at 100."
##
## WHAT IS BUILT: the expanding ring visual at exactly RADIUS_PX, the 1 s
## timing, the invulnerability window, and the ready/fired signals.
## WHAT IS NOT: finding and affecting what is inside the radius.

# --------------------------------------------------------------------------
# GDD numbers - section 4, Shockwave
# --------------------------------------------------------------------------

## "Cost: All 100 meter points"
const COST: int = 100
## "Radius: 150 px around the player"
const RADIUS_PX: float = 150.0
## "Effect on enemies: 30 damage and 50 px knockback"
const ENEMY_DAMAGE: int = 30
const KNOCKBACK_PX: float = 50.0
## "Activation: 1 s animation; player is invulnerable for that second"
const ACTIVATION_SECONDS: float = 1.0

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal became_ready
signal fired(at: Vector2)
signal finished

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

var is_ready: bool = false
var is_firing: bool = false

@onready var player: Player = get_parent() as Player
@onready var graze_meter: GrazeMeter = get_parent().get_node("GrazeMeter")
@onready var ring: Line2D = $Ring


func _ready() -> void:
	ring.visible = false
	_build_ring()
	# Built wiring: the meter tells us when we are armed.
	if graze_meter:
		graze_meter.meter_full.connect(_on_meter_full)
		graze_meter.meter_no_longer_full.connect(func() -> void: is_ready = false)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shockwave"):
		try_fire()


func try_fire() -> bool:
	if not is_ready or is_firing:
		return false
	_fire()
	return true


func _fire() -> void:
	is_firing = true
	is_ready = false

	# Built: spend the meter, open the invulnerability window, play the ring.
	graze_meter.spend_all()
	player.is_invulnerable = true
	fired.emit(player.global_position)
	_play_ring()
	if GameManager.instance:
		GameManager.instance.shake(7.0)

	# TODO(Daryl): with the ring playing, apply the effects inside RADIUS_PX:
	#
	#   bullets  - "Destroys every enemy bullet in the radius". Also note the
	#              cross-link to Bullet Grazing: clearing them means the
	#              player must move back into fire to graze again.
	#   enemies  - ENEMY_DAMAGE damage and KNOCKBACK_PX knockback away from
	#              the player. The knockback "can push enemies onto traps"
	#              (cross-link to K'von's Environmental Combat).
	#   barrels  - "Barrels inside the 150 px radius detonate at once."
	#              Call EnvObject.detonate() on each.
	#
	# Player.tscn has no detection area for this on purpose: a one-shot
	# radius query is cleaner than a permanent 150 px Area2D.
	#
	# PREVIEW(Daryl): exactly that, by group.
	var origin := player.global_position
	for b in get_tree().get_nodes_in_group("enemy_bullet"):
		if b is Node2D and (b as Node2D).global_position.distance_to(origin) <= RADIUS_PX:
			b.queue_free()
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Enemy and (e as Enemy).global_position.distance_to(origin) <= RADIUS_PX:
			var away := ((e as Enemy).global_position - origin).normalized()
			(e as Enemy).apply_knockback(away * KNOCKBACK_PX)
			(e as Enemy).take_damage(ENEMY_DAMAGE, "player")
	for o in get_tree().get_nodes_in_group("env_object"):
		if o is EnvObject and (o as EnvObject).kind == EnvObject.Kind.BARREL \
				and (o as EnvObject).global_position.distance_to(origin) <= RADIUS_PX:
			(o as EnvObject).detonate()

	# Built: the 1 s window closes on its own, whatever the effects do.
	await get_tree().create_timer(ACTIVATION_SECONDS).timeout
	player.is_invulnerable = false
	is_firing = false
	finished.emit()


func _on_meter_full() -> void:
	is_ready = true
	became_ready.emit()


# --------------------------------------------------------------------------
# Visuals - built
# --------------------------------------------------------------------------

## The ring is drawn at radius 1 and scaled, so the tween below animates it
## from the player outward to exactly RADIUS_PX. If the GDD number changes,
## the visual follows automatically.
func _build_ring() -> void:
	ring.clear_points()
	var segments := 48
	for i in range(segments + 1):
		var a := TAU * float(i) / float(segments)
		ring.add_point(Vector2(cos(a), sin(a)))
	ring.width = 3.0
	ring.default_color = Palette.SHOCKWAVE_RING  # Graze Gold, per the palette
	ring.z_index = 6


func _play_ring() -> void:
	ring.visible = true
	ring.scale = Vector2(0.08, 0.08)
	ring.modulate = Color(1, 1, 1, 1)

	var tween := create_tween()
	tween.set_parallel(true)
	# Expand to the real radius over most of the activation second, easing out
	# so the leading edge is fast - the player reads the clear instantly.
	tween.tween_property(ring, "scale", Vector2(RADIUS_PX, RADIUS_PX),
			ACTIVATION_SECONDS * 0.7).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, ACTIVATION_SECONDS * 0.7)
	tween.chain().tween_callback(func() -> void: ring.visible = false)
