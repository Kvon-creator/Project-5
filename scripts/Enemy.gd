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
const HP_BY_TIER := {"standard": 40, "elite": 120, "boss": 1200}

## The bestiary, and which GDD tier each creature belongs to. Species decides
## how it LOOKS and behaves; tier decides HP and kill energy. Keeping them
## separate means a second standard-tier creature costs a sprite sheet and
## one line here, not a balance rewrite.
const SPECIES_TIER := {
	"snail": "standard",      # melee, slow, hard front
	"hare": "standard",       # ranged - holds 150-250 px, takes cover
	"grotesque": "elite",     # from room 4
	"scribe": "boss",         # room 8
}

## Which species default to ranged behaviour.
const RANGED_SPECIES := ["hare", "scribe"]

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

# PREVIEW(Jarman) numbers - not in the GDD, chosen so each species reads
# differently at a glance. Flagged for playtesting.
const SPECIES_SPEED := {"snail": 55.0, "hare": 95.0, "grotesque": 120.0, "scribe": 40.0}
const MELEE_DAMAGE: int = 10              ## same as a bullet, per hit
const MELEE_COOLDOWN_SECONDS: float = 1.0
const MELEE_REACH_PX: float = 14.0        ## beyond the two hitboxes touching
const FIRE_INTERVAL := {"hare": 1.4, "scribe": 2.5}
const FIRE_RANGE_PX: float = 460.0
const SCRIBE_RING_BULLETS: int = 12
const SEPARATION_PX: float = 34.0         ## enemies shoulder each other apart
## Shockwave supplies the distance. This controls only how quickly collision-
## safe knockback is consumed, not how far the enemy travels.
const KNOCKBACK_SPEED_PX_PER_SECOND: float = 500.0
const ENEMY_BULLET_SCENE: PackedScene = preload("res://scenes/EnemyBullet.tscn")

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal died(enemy: Enemy)
signal hp_changed(hp: int, max_hp: int)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

@export var species: String = "snail"   ## snail | hare | grotesque | scribe
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

## PREVIEW(Jarman) state.
var _target: Vector2 = Vector2.INF   ## where the current "path" is headed
var _melee_cooldown: float = 0.0
var _fire_cooldown: float = 1.0      ## first shot comes after a beat, not on spawn
var _knockback_remaining: Vector2 = Vector2.ZERO
var _volley: int = 0
var _anim_t: float = 0.0

const DIRECTION_NAMES: Array[String] = [
	"SE", "E", "NE", "N", "NW", "W", "SW", "S"
]

@onready var sprite: AnimatedSprite2D = $Sprite
@onready var hitbox: CollisionShape2D = $Hitbox


## The GDD tier this creature counts as, for HP and for kill energy.
func tier() -> String:
	return SPECIES_TIER.get(species, "standard")


## Point the sprite at this species' SpriteFrames. Enemy.tscn carries one set
## per species, so a single scene covers the whole bestiary and RoomManager
## only has to set `species` when it spawns.
func _apply_species_frames() -> void:
	var key := "frames_%s" % species
	if has_meta(key):
		sprite.sprite_frames = get_meta(key)
	# The scene also carries, per species, where the sprite sits over the
	# feet, how big its shadow is, and its hitbox. All optional.
	if has_meta("offset_%s" % species):
		sprite.offset = Vector2(0, float(get_meta("offset_%s" % species)))
	var shadow := get_node_or_null("Shadow") as Node2D
	if shadow and has_meta("shadow_%s" % species):
		shadow.scale = get_meta("shadow_%s" % species)
	if has_meta("hitbox_%s" % species):
		hitbox.shape = get_meta("hitbox_%s" % species)


func _ready() -> void:
	max_hp = HP_BY_TIER.get(tier(), 40)
	hp = max_hp
	is_ranged = is_ranged or species in RANGED_SPECIES
	add_to_group("enemy")
	_apply_species_frames()
	_apply_facing(facing)
	hp_changed.emit(hp, max_hp)


func _physics_process(delta: float) -> void:
	if _is_dying:
		return

	# Shockwave knockback is a requested displacement, not an approximate
	# velocity. Consume exactly that displacement with move_and_collide(), which
	# stops safely at walls/cover while still allowing Area2D traps to trigger.
	# Normal AI movement pauses briefly so 50 px in open space remains 50 px.
	if _apply_knockback_step(delta):
		velocity = Vector2.ZERO
		_animate(delta)
		return

	# Built: keep the sprite pointing along the movement/aim direction.
	if velocity.length_squared() > 1.0:
		facing = velocity.normalized()
	_apply_facing(facing)

	# Built: the recalculation clock, including the boosted rate. The timer
	# fires `_recalculate_path()`.
	_path_timer -= delta
	if _path_timer <= 0.0:
		_path_timer = current_path_recalc_interval()
		_recalculate_path()

	# PREVIEW(Jarman): move straight at the target, shoulder other enemies
	# aside and let move_and_slide handle the walls.
	var player := _player()
	var speed: float = SPECIES_SPEED.get(species, 60.0)
	var desired := Vector2.ZERO
	if _target != Vector2.INF and global_position.distance_to(_target) > 6.0:
		desired = (_target - global_position).normalized() * speed
	for other in get_tree().get_nodes_in_group("enemy"):
		if other == self or not (other is Node2D):
			continue
		var away: Vector2 = global_position - (other as Node2D).global_position
		var d := away.length()
		if d > 0.01 and d < SEPARATION_PX:
			desired += away / d * (SEPARATION_PX - d) * 3.0
	velocity = desired
	move_and_slide()

	# A ranged enemy that is standing still still watches the player.
	if velocity.length_squared() <= 1.0 and player:
		facing = (player.global_position - global_position).normalized()
		_apply_facing(facing)

	_melee_cooldown = maxf(0.0, _melee_cooldown - delta)
	_fire_cooldown -= delta
	if player and not player.is_dead:
		var dist := global_position.distance_to(player.global_position)
		if not is_ranged and _melee_cooldown <= 0.0 \
				and dist <= _hitbox_radius() + 8.0 + MELEE_REACH_PX:
			_melee(player)
		if is_ranged and _fire_cooldown <= 0.0 and dist <= FIRE_RANGE_PX:
			_fire_cooldown = float(FIRE_INTERVAL.get(species, 1.5))
			_shoot(player)
	_animate(delta)


func _player() -> Player:
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.player):
		return gm.player
	return null


func _hitbox_radius() -> float:
	var c := hitbox.shape as CircleShape2D
	return c.radius if c else 14.0


## PREVIEW(Jarman): a lick of the spear / a bite. Same 10 as a bullet.
func _melee(player: Player) -> void:
	_melee_cooldown = MELEE_COOLDOWN_SECONDS
	player.take_damage(MELEE_DAMAGE)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(1.15, 0.9), 0.06)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.12)


## PREVIEW(Jarman): the hare fires one aimed arrow; the scribe alternates a
## full ring with an aimed three-shot, which is what the boss arena
## reference shows.
func _shoot(player: Player) -> void:
	var aim := (player.global_position - global_position).normalized()
	if species == "scribe":
		_volley += 1
		if _volley % 2 == 1:
			for i in SCRIBE_RING_BULLETS:
				_spawn_bullet(Vector2.RIGHT.rotated(TAU * float(i) / SCRIBE_RING_BULLETS))
		else:
			for a in [-0.18, 0.0, 0.18]:
				_spawn_bullet(aim.rotated(a))
	else:
		_spawn_bullet(aim)
	var tween := create_tween()
	tween.tween_property(sprite, "scale", Vector2(0.92, 1.08), 0.05)
	tween.tween_property(sprite, "scale", Vector2.ONE, 0.1)


func _spawn_bullet(dir: Vector2) -> void:
	var b := ENEMY_BULLET_SCENE.instantiate()
	b.set("direction", dir)
	b.global_position = global_position + Vector2(0, -18) + dir * 16.0
	get_tree().current_scene.add_child(b)


## Shockwave and barrels push enemies: `offset` is the requested displacement
## in pixels. In unobstructed space the full vector is consumed exactly.
func apply_knockback(offset: Vector2) -> void:
	_knockback_remaining += offset


func _apply_knockback_step(delta: float) -> bool:
	if _knockback_remaining.length_squared() <= 0.0001:
		_knockback_remaining = Vector2.ZERO
		return false
	var step := _knockback_remaining.limit_length(
			KNOCKBACK_SPEED_PX_PER_SECOND * delta)
	var collision := move_and_collide(step)
	if collision:
		_knockback_remaining = Vector2.ZERO
	else:
		_knockback_remaining -= step
		if _knockback_remaining.length_squared() <= 0.0001:
			_knockback_remaining = Vector2.ZERO
	return true


func is_knockback_active() -> bool:
	return _knockback_remaining.length_squared() > 0.0001


## Breathing while still, a bob while moving. Visual only.
func _animate(delta: float) -> void:
	_anim_t += delta
	if velocity.length_squared() > 4.0:
		var rate := 10.0 if species != "snail" else 5.0
		sprite.position.y = -absf(sin(_anim_t * rate)) * 2.5
	else:
		sprite.position.y = lerpf(sprite.position.y, 0.0, 0.3)


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
	# PREVIEW(Jarman): no pathing yet - a melee enemy heads straight for the
	# player, a ranged one heads for the nearest point of its stand-off band,
	# and drifts sideways once it is in the band so it is not a sitting duck.
	var player := _player()
	if player == null:
		_target = Vector2.INF
		return
	if not is_ranged:
		_target = player.global_position
		return
	var band := current_ranged_band()
	var to_me := global_position - player.global_position
	var dist := to_me.length()
	var mid: float = (float(band[0]) + float(band[1])) * 0.5
	if dist < 1.0:
		to_me = Vector2.RIGHT
	if dist < float(band[0]) or dist > float(band[1]):
		_target = player.global_position + to_me.normalized() * mid
	else:
		var side := 1.0 if randf() < 0.5 else -1.0
		_target = player.global_position + to_me.normalized().rotated(0.7 * side) * mid
	# TODO(Jarman): Enemy Adaptation proper, due Dec 2:
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

	# PREVIEW(Jarman): the HP maths.
	hp = maxi(0, hp - amount)
	hp_changed.emit(hp, max_hp)
	if hp == 0:
		die()


func die() -> void:
	if _is_dying:
		return
	_is_dying = true
	# Built: tell CombatRewards, with the type and the killed-by source it
	# needs. Wired here because it is a cross-script link.
	CombatRewards.register_kill(tier(), killed_by, global_position)
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
	var dir_name := direction_name_for(v)
	var anim := "idle_%s" % dir_name
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim) \
			and sprite.animation != anim:
		sprite.play(anim)
	# Reference cut-outs are one view drawn facing right: mirror for left.
	if sprite.sprite_frames:
		var a := sprite.sprite_frames.get_frame_texture("idle_E", 0)
		var b := sprite.sprite_frames.get_frame_texture("idle_W", 0)
		sprite.flip_h = a != null and a == b and dir_name in ["W", "NW", "SW"]
