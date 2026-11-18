class_name Dodge
extends Node
## The dodge: SPACE, always available. NOT IN THE GDD - every number here is
## proposed, for playtesting.
##
## A quick burst along the move direction (or the aim, standing still) with
## i-frames: for DODGE_IFRAMES seconds nothing hurts the knight - bullets,
## melee, the boss's lunge, traps, barrel blasts.
##
## How it works alongside Bullet Grazing: during the i-frames enemy bullets
## pass THROUGH the knight instead of breaking on him (EnemyBullet asks
## Player.is_phasing()). A bullet that passes through his graze band without
## hitting him is a graze by the GDD's own rule, so dodging straight through
## a bullet pays +5 when it leaves the band - the dodge is a way to graze, not
## a way around grazing. A bullet still inside his hitbox when the i-frames
## end hits him then, so the timing matters.
##
## The Shadow Step item (Items.gd) upgrades it: further, faster to recover,
## longer i-frames.

signal dodged(direction: Vector2)
## For the HUD's SPACE slot. `remaining` is 0 when ready.
signal cooldown_changed(remaining: float, total: float)

const DISTANCE_PX: float = 110.0
const SECONDS: float = 0.22
const IFRAMES: float = 0.30          # the dodge plus a short tail
const COOLDOWN: float = 0.8

var _time: float = 0.0               # dodge movement left
var _iframes: float = 0.0            # invulnerability left
var _cooldown: float = 0.0
var _dir: Vector2 = Vector2.ZERO
var _distance: float = DISTANCE_PX
var _seconds: float = SECONDS
var _afterimage_t: float = 0.0

@onready var player: Player = get_parent() as Player


func _ready() -> void:
	cooldown_changed.emit.call_deferred(0.0, cooldown_total())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("dodge"):
		try_dodge()


func upgraded() -> bool:
	return player != null and player.loadout != null and player.loadout.has("shadow_step")


func cooldown_total() -> float:
	return Items.SHADOW_STEP_COOLDOWN if upgraded() else COOLDOWN


func is_dodging() -> bool:
	return _time > 0.0


func is_invulnerable() -> bool:
	return _iframes > 0.0


func is_ready() -> bool:
	return _cooldown <= 0.0 and not is_dodging()


## The velocity Player.gd moves at while a dodge is on.
func velocity() -> Vector2:
	return _dir * (_distance / _seconds)


## Start a dodge along the move input, or the aim if standing still.
func try_dodge() -> bool:
	if player == null or player.is_dead or not is_ready():
		return false
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = player.aim_direction
	_dir = dir.normalized()
	var up := upgraded()
	_distance = Items.SHADOW_STEP_DISTANCE_PX if up else DISTANCE_PX
	_seconds = Items.SHADOW_STEP_SECONDS if up else SECONDS
	_time = _seconds
	_iframes = Items.SHADOW_STEP_IFRAMES if up else IFRAMES
	_cooldown = cooldown_total()
	_afterimage_t = 0.0
	player.sprite.modulate.a = 0.55
	dodged.emit(_dir)
	return true


func _physics_process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
		cooldown_changed.emit(_cooldown, cooldown_total())
	if _time > 0.0:
		_time -= delta
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = 0.035
			_afterimage()
	if _iframes > 0.0:
		_iframes -= delta
		if _iframes <= 0.0 and is_instance_valid(player) and not player.is_dead:
			player.sprite.modulate.a = 1.0


## A fading teal copy of the knight's current frame, left behind.
func _afterimage() -> void:
	var src := player.sprite
	if src == null or src.sprite_frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = src.sprite_frames.get_frame_texture(src.animation, src.frame)
	ghost.flip_h = src.flip_h
	ghost.offset = src.offset
	ghost.global_position = src.global_position
	ghost.scale = src.global_scale
	ghost.modulate = Color(Palette.NIB_TEAL, 0.4)
	ghost.z_index = 3
	get_tree().current_scene.add_child(ghost)
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.22)
	t.tween_callback(ghost.queue_free)
