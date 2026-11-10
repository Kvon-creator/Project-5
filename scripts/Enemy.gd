class_name Enemy
extends CharacterBody2D
## Enemy base, and Mechanic 5: Enemy Adaptation.
##
## OWNER of the base script: Jarman (proposed), by Nov 18.
## OWNER of Enemy Adaptation: Jarman, due Dec 2.
## GDD architecture box: "Enemy.gd / Enemy.tscn / HP, type, killed-by source /
## Enemy Adaptation: path, 2 s timer, hazards seen".
## Reads: Player, EnvObject, CombatRewards
##        ("Chase target; cover and hazards in 200 px; boost active").
##
## This is the second hub - four scripts read enemies. Keep the public surface
## stable.
##
## WHAT IS BUILT: the sprite with 8-direction facing, the three tier visuals,
## the damage flash, the death fade, and the killed-by bookkeeping that
## CombatRewards needs for its double-energy rule.
## WHAT IS NOT: pathing, hazard avoidance, shooting.

# --------------------------------------------------------------------------
# GDD numbers - section 5, Enemy Adaptation, and the player baseline table
# --------------------------------------------------------------------------

## "Enemy HP: standard / elite / boss  40 / 120 / 1,200"
const HP_BY_TYPE := {"standard": 40, "elite": 120, "boss": 1200}

## "Obstacle detection: Within 200 px"
const OBSTACLE_DETECTION_PX: float = 200.0
## "Hazard avoidance: Steers clear of active hazards within 75 px"
const HAZARD_AVOID_PX: float = 75.0
## "Path recalculation: Every 2 s"
const PATH_RECALC_SECONDS: float = 2.0
## "Ranged enemy distance: Keeps 150-250 px from the player, behind cover
## when cover is in range"
const RANGED_MIN_PX: float = 150.0
const RANGED_MAX_PX: float = 250.0

## Cross-link, Jarman -> Jarman (new): "While the +20% damage boost is active,
## ranged enemies back off to 200-300 px and recalculate paths every 1 s
## instead of 2 s."
const RANGED_MIN_BOOSTED_PX: float = 200.0
const RANGED_MAX_BOOSTED_PX: float = 300.0
const PATH_RECALC_BOOSTED_SECONDS: float = 1.0

## "Enemy bullet damage 10"
const BULLET_DAMAGE: int = 10

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal died(enemy: Enemy)
signal hp_changed(hp: int, max_hp: int)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

@export var enemy_type: String = "standard"   ## "standard" | "elite" | "boss"
@export var is_ranged: bool = false

var hp: int = 40
var max_hp: int = 40

## The GDD's "killed-by source". CombatRewards reads this to decide whether
## the kill pays double: "An enemy killed by a barrel or trap pays double
## energy (10 / 30 / 60)". Set it BEFORE calling take_damage, via the
## `source` argument.
var killed_by: String = "player"

var facing: Vector2 = Vector2(1, 1).normalized()
var _path_timer: float = 0.0
var _is_dying: bool = false

const DIRECTION_NAMES: Array[String] = [
	"SE", "E", "NE", "N", "NW", "W", "SW", "S"
]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: CollisionShape2D = $Hitbox


func _ready() -> void:
	max_hp = HP_BY_TYPE.get(enemy_type, 40)
	hp = max_hp
	add_to_group("enemy")
	_apply_facing(facing)
	hp_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	if _is_dying:
		return

	# Built: keep the sprite pointing along the movement/aim direction.
	if velocity.length_squared() > 1.0:
		facing = velocity.normalized()
	_apply_facing(facing)

	# Built: the recalculation clock, including the boosted rate. The timer
	# fires `_recalculate_path()`; filling that in is the remaining work.
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = current_path_recalc_interval()
		_recalculate_path()

	# TODO(Jarman): move along the current path with move_and_slide().


## The recalc interval right now, honouring the damage-boost cross-link.
func current_path_recalc_interval() -> float:
	return PATH_RECALC_BOOSTED_SECONDS if CombatRewards.is_boosted \
			else PATH_RECALC_SECONDS


## The stand-off band a ranged enemy wants to hold, as [min, max].
func current_ranged_band() -> Array:
	if CombatRewards.is_boosted:
		return [RANGED_MIN_BOOSTED_PX, RANGED_MAX_BOOSTED_PX]
	return [RANGED_MIN_PX, RANGED_MAX_PX]


func _recalculate_path() -> void:
	# TODO(Jarman): Enemy Adaptation, all of it:
	#   - find walls and destructible cover within OBSTACLE_DETECTION_PX and
	#     route around them while chasing the player
	#   - find ACTIVE hazards within HAZARD_AVOID_PX and steer clear. This is
	#     the rule that makes K'von's double-energy environmental kills a
	#     skill check: "the double-energy environmental kills only happen
	#     when the player lures or knocks enemies in"
	#   - ranged enemies hold current_ranged_band() from the player, behind
	#     cover when cover is in range
	#
	# Enemy.tscn has a NavigationAgent2D ready for this; Room.tscn's walls
	# are already baked into a navigation region.
	pass


# --------------------------------------------------------------------------
# Damage and death - visuals built, HP maths is not
# --------------------------------------------------------------------------

## `source` is "player", "barrel" or "trap" - whatever dealt the blow. It is
## recorded so CombatRewards can apply the double-energy rule on death.
func take_damage(amount: int, source: String = "player") -> void:
	if _is_dying:
		return
	killed_by = source
	_flash(Palette.DAMAGE_FLASH)

	# TODO(Jarman): hp = maxi(0, hp - amount); emit hp_changed; call die()
	# when hp reaches 0.


func die() -> void:
	if _is_dying:
		return
	_is_dying = true
	# Built: tell CombatRewards, with the type and the killed-by source it
	# needs. Wired here because it is a cross-script link.
	CombatRewards.register_kill(enemy_type, killed_by, global_position)
	died.emit(self)
	_play_death()


func _flash(colour: Color, duration: float = 0.10) -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", colour, duration * 0.3)
	tween.tween_property(sprite, "modulate", Color.WHITE, duration * 0.7)


func _play_death() -> void:
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate", Palette.BLOOD_RUST, 0.12)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.35)
	tween.tween_property(self, "scale", scale * 1.15, 0.35)
	tween.chain().tween_callback(queue_free)


# --------------------------------------------------------------------------
# Facing - built
# --------------------------------------------------------------------------

func direction_name_for(v: Vector2) -> String:
	if v.length_squared() < 0.0001:
		return DIRECTION_NAMES[0]
	var angle := atan2(-v.y, v.x) + deg_to_rad(45.0)
	var index := int(round(angle / deg_to_rad(45.0))) % DIRECTION_NAMES.size()
	if index < 0:
		index += DIRECTION_NAMES.size()
	return DIRECTION_NAMES[index]


func _apply_facing(v: Vector2) -> void:
	var anim := "idle_%s" % direction_name_for(v)
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) \
			and sprite.animation != anim:
		sprite.play(anim)
