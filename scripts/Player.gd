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
signal died
signal took_damage(amount: int)
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


func _physics_process(_delta: float) -> void:
	# Keep the sprite pointing where the player aims. This works now and is
	# independent of whether movement is implemented, so Daryl can fill in
	# the TODOs below without touching the visuals.
	_apply_facing(aim_direction)

	# TODO(Daryl): read move_up/down/left/right, set velocity to the input
	# direction * MOVE_SPEED, then move_and_slide().
	# TODO(Daryl): set aim_direction from
	# (get_global_mouse_position() - global_position).normalized().
	# TODO(Daryl): while "shoot" is held, fire at SHOTS_PER_SECOND using a
	# Timer or an accumulator; damage is SHOT_DAMAGE * damage_multiplier.
	# Emit fired_shot(muzzle.global_position, aim_direction) so audio and
	# muzzle flash hook on without this script knowing about them.
	pass


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


# --------------------------------------------------------------------------
# Damage - visual feedback is built, the HP maths is not
# --------------------------------------------------------------------------

## GDD: "Enemy bullet damage 10 (10 hits from full HP)".
## Taking damage also costs the Graze Meter 25 points, which GrazeMeter.gd
## handles by listening to took_damage.
func take_damage(amount: int) -> void:
	if is_invulnerable:
		return

	# Built: the damage flash, in Blood Rust per the GDD palette table
	# ("Traps, damage flashes").
	_flash(Palette.DAMAGE_FLASH)
	took_damage.emit(amount)

	# TODO(Daryl): hp = clampi(hp - amount, 0, MAX_HP), emit hp_changed,
	# and emit died when hp hits 0. GameManager listens for died and ends
	# the run ("Lose: player HP reaches 0 in any room").
	pass


## GDD: "Room-clear heal +10 HP, capped at 100 (proposed)".
func heal_room_clear() -> void:
	# TODO(Daryl): hp = mini(hp + ROOM_CLEAR_HEAL, MAX_HP); emit hp_changed.
	pass


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
