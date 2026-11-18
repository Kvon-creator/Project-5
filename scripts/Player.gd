class_name Player
extends CharacterBody2D
## The player character.
##
## GDD owner of the SUPPORT script: Daryl Watkins-Mattocks (proposed), by Nov 18.
## GDD architecture box: "Player.gd / Player.tscn / HP 0-100, move, aim, shoot,
## damage multiplier".
##
## This is one of the two hubs. From the GDD:
##     Player.gd and Enemy.gd are the hubs: five scripts read the player, four
##     read enemies.
## The five readers are GameManager, HUD, GrazeMeter, Enemy and EnvObject. Keep
## the public surface at the top of this file stable, because changing it
## breaks all five.
##
## WHAT IS BUILT: the whole visual side. Sprite, 8-direction facing, the
## AnimatedSprite2D wiring, hitbox, graze area, damage flash, death fade.
## WHAT IS NOT: movement, aiming, shooting, HP. Every one of those is a
## `TODO(Daryl)` below.

# --------------------------------------------------------------------------
# GDD numbers - Player baseline (proposed)
# --------------------------------------------------------------------------

const MAX_HP: int = 100                  ## Player HP 100
const MOVE_SPEED: float = 220.0          ## Move speed 220 px/s
const SHOT_DAMAGE: int = 10              ## Player shot damage 10 per shot
const SHOTS_PER_SECOND: float = 6.0      ## 6 shots per s (hold left-click)
const ROOM_CLEAR_HEAL: int = 10          ## Room-clear heal +10 HP, cap 100

## The GDD's gameplay-space scale: "1 m = 32 px".
const PX_PER_METRE: int = 32

# --------------------------------------------------------------------------
# Signals - the five readers listen to these instead of polling
# --------------------------------------------------------------------------

signal hp_changed(hp: int, max_hp: int)
@warning_ignore("unused_signal")
signal died
signal took_damage(amount: int)
@warning_ignore("unused_signal")
signal fired_shot(from: Vector2, direction: Vector2)
## Emitted whenever facing changes to a new one of the 8 directions. The HUD
## does not need it, but it is the hook for footstep audio and dust later.
signal facing_changed(direction_name: String)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

var hp: int = MAX_HP

## Set by CombatRewards while the +20% damage power-up is active.
## GDD: "Player.gd reads CombatRewards / Damage multiplier while boosted".
var damage_multiplier: float = 1.0

## Unit vector the player is aiming at. Drives which of the 8 sprites shows.
var aim_direction: Vector2 = Vector2(1, 1).normalized()

var is_invulnerable: bool = false

## Set by GameManager when the run is lost; the corpse stops taking input.
var is_dead: bool = false

## PREVIEW(Daryl): the bits movement and shooting need.
const PLAYER_BULLET_SCENE: PackedScene = preload("res://scenes/PlayerBullet.tscn")
## A short mercy window after a hit, so one bullet stream is not an instant
## 10-hit death. Not in the GDD - a preview number, flagged for playtesting.
const HIT_INVULNERABLE_SECONDS: float = 0.4
var _shot_cooldown: float = 0.0
var _hit_timer: float = 0.0
var _anim_t: float = 0.0

# --------------------------------------------------------------------------
# Visual wiring - built, working, do not need changing to add mechanics
# --------------------------------------------------------------------------

## Sprite frame names, matching the 8 files the Blender pipeline writes.
## Index 0 is the anchor pose (down-right). Counter-clockwise from there.
const DIRECTION_NAMES: Array[String] = [
	"SE", "E", "NE", "N", "NW", "W", "SW", "S"
]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: CollisionShape2D = $Hitbox
@onready var graze_area: Area2D = $GrazeArea
@onready var graze_meter: Node = $GrazeMeter
@onready var shockwave: Node2D = $Shockwave
@onready var muzzle: Marker2D = $Muzzle

var _current_direction: String = "SE"


func _ready() -> void:
	_apply_facing(aim_direction)
	hp_changed.emit(hp, MAX_HP)
	# Catch any magenta that creeps onto the player. The GDD reserves it for
	# enemy bullets alone.
	Palette.check_no_magenta(self)


func _physics_process(delta: float) -> void:
	if is_dead:
		velocity = Vector2.ZERO
		return

	# PREVIEW(Daryl): movement. Input.get_vector already normalises
	# diagonals, so the GDD's 220 px/s holds in every direction.
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input * MOVE_SPEED
	move_and_slide()

	# PREVIEW(Daryl): aim at the mouse.
	var to_mouse := get_global_mouse_position() - global_position
	if to_mouse.length_squared() > 1.0:
		aim_direction = to_mouse.normalized()
	_apply_facing(aim_direction)

	# PREVIEW(Daryl): hold to fire at SHOTS_PER_SECOND.
	_shot_cooldown -= delta
	if Input.is_action_pressed("shoot") and _shot_cooldown <= 0.0:
		_shot_cooldown = 1.0 / SHOTS_PER_SECOND
		_fire()

	_hit_timer = maxf(0.0, _hit_timer - delta)
	_animate(delta, input.length_squared() > 0.01)


## One shot: a PlayerBullet from just ahead of the knight, in Nib Teal.
func _fire() -> void:
	var bullet := PLAYER_BULLET_SCENE.instantiate()
	var from := global_position + aim_direction * 18.0 + Vector2(0, -14)
	bullet.global_position = from
	bullet.set("direction", aim_direction)
	# The boost can be read off either the local multiplier or the autoload;
	# take the larger so it is never counted twice.
	var mult := maxf(damage_multiplier, CombatRewards.damage_multiplier)
	bullet.set("damage", int(round(SHOT_DAMAGE * mult)))
	get_tree().current_scene.add_child(bullet)
	fired_shot.emit(from, aim_direction)
	# A tiny recoil squash so firing reads even without a muzzle flash.
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.94, 1.06), 0.04)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.08)


## Breathing while still, a bob while walking. Visual only.
func _animate(delta: float, moving: bool) -> void:
	_anim_t += delta
	if moving:
		sprite.position.y = -absf(sin(_anim_t * 14.0)) * 3.0
	else:
		sprite.position.y = lerpf(sprite.position.y, 0.0, 0.3)
		sprite.scale.y = lerpf(sprite.scale.y, 1.0 + 0.02 * sin(_anim_t * 2.5), 0.2)


## Snap a continuous aim vector to one of the 8 sprite directions.
##
## This is the piece that makes a 2D game out of 8 rendered angles, so it is
## written out rather than left as a TODO. Screen Y grows downward in Godot,
## so the angle is negated before bucketing: that way "down-right" on screen
## lands on the SE sprite, which is the anchor pose.
func direction_name_for(v: Vector2) -> String:
	if v.length_squared() < 0.0001:
		return _current_direction
	# atan2 with -y puts 0 at screen-right and grows counter-clockwise.
	var angle := atan2(-v.y, v.x)
	# The anchor sprite SE faces down-right, which is -45 degrees on screen.
	# Shift so that bucket 0 is centred on it, then quantise to 45 degree steps.
	var shifted := angle + deg_to_rad(45.0)
	var index := int(round(shifted / deg_to_rad(45.0))) % DIRECTION_NAMES.size()
	if index < 0:
		index += DIRECTION_NAMES.size()
	return DIRECTION_NAMES[index]


func _apply_facing(v: Vector2) -> void:
	# Named dir_name, not name: `name` is a property on Node, and shadowing
	# it here would warn on every build.
	var dir_name := direction_name_for(v)
	if dir_name == _current_direction:
		return
	_current_direction = dir_name
	facing_changed.emit(dir_name)
	var anim := "idle_%s" % dir_name
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
	# The reference cut-out is one side view drawn facing right, so the
	# left-facing names mirror it. The Blender set carries all 8 views and
	# ignores this because each of its frames already faces the right way.
	sprite.flip_h = dir_name in ["W", "NW", "SW"] and _single_view_sprites()


## True when every direction shares one texture (the reference cut-outs).
func _single_view_sprites() -> bool:
	if sprite.sprite_frames == null:
		return false
	var a := sprite.sprite_frames.get_frame_texture("idle_E", 0)
	var b := sprite.sprite_frames.get_frame_texture("idle_W", 0)
	return a != null and a == b


# --------------------------------------------------------------------------
# Damage - visual feedback is built, the HP maths is not
# --------------------------------------------------------------------------

## GDD: "Enemy bullet damage 10 (10 hits from full HP)".
## Taking damage also costs the Graze Meter 25 points, which GrazeMeter.gd
## handles by listening to took_damage.
func take_damage(amount: int) -> void:
	if is_invulnerable or is_dead or _hit_timer > 0.0:
		return

	# Built: the damage flash, in Blood Rust per the GDD palette table
	# ("Traps, damage flashes").
	_flash(Palette.DAMAGE_FLASH)
	took_damage.emit(amount)

	# PREVIEW(Daryl): the HP maths.
	hp = clampi(hp - amount, 0, MAX_HP)
	hp_changed.emit(hp, MAX_HP)
	_hit_timer = HIT_INVULNERABLE_SECONDS
	if hp == 0:
		died.emit()


## GDD: "Room-clear heal +10 HP, capped at 100 (proposed)".
func heal_room_clear() -> void:
	# PREVIEW(Daryl)
	hp = mini(hp + ROOM_CLEAR_HEAL, MAX_HP)
	hp_changed.emit(hp, MAX_HP)


## A one-shot colour pulse on the sprite. Used for damage, and reusable for
## any other hit feedback.
func _flash(colour: Color, duration: float = 0.12) -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", colour, duration * 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, duration * 0.7)


## Built: the death visual. GameManager decides what a death MEANS; this just
## plays it. GDD: "The run ends and the player restarts at room 1".
func play_death() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Palette.BLOOD_RUST, 0.25)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.6)
	tween.tween_property(self, "scale", Vector2(0.85, 0.85), 0.6)
