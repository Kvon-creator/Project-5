extends Node
## Mechanic 6: Combat Rewards. Autoloaded as `CombatRewards`.
##
## OWNER: Jarman. Due Nov 18.
## GDD architecture box: "CombatRewards.gd / autoload / Combat Rewards:
## kill count (every 5th), boost timer 0-10 s".
## Reads: Enemy, GrazeMeter
##        ("Enemy type and killed-by source; add energy up to 100").
##
## GDD input: "none; triggers on each enemy defeat."
##
## This is an autoload with no scene, so it is the one script every other
## mechanic can reach without a node path. Two other mechanics depend on it:
##   - Player.gd reads `damage_multiplier` while the boost is active
##   - GrazeMeter gains kill energy, a second way to charge Shockwave
##
## WHAT IS BUILT: the timer, the signals, the multiplier value, and the
## double-energy rule for environmental kills.
## WHAT IS NOT: hooking it to actual enemy deaths.

# --------------------------------------------------------------------------
# GDD numbers - section 6, Combat Rewards
# --------------------------------------------------------------------------

## "Energy per kill: Standard 5, elite 15, boss 30; added to the Graze Meter
## up to 100"
const ENERGY_STANDARD: int = 5
const ENERGY_ELITE: int = 15
const ENERGY_BOSS: int = 30

## Cross-link, K'von -> Jarman (new): "An enemy killed by a barrel or trap
## pays double energy (10 / 30 / 60) and still counts toward the every-5th-kill
## power-up."
const ENVIRONMENTAL_ENERGY_MULTIPLIER: int = 2

## "Damage power-up drop: Every 5th enemy defeated"
const KILLS_PER_POWERUP: int = 5
## "Power-up effect: +20% weapon damage for 10 s"
const POWERUP_DAMAGE_BONUS: float = 0.20
const POWERUP_DURATION: float = 10.0

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal energy_awarded(amount: int, was_environmental: bool)
signal powerup_dropped(at: Vector2)
signal boost_started(duration: float)
signal boost_ended
## Emitted every frame the boost is running, for the HUD's countdown bar.
signal boost_time_changed(remaining: float, duration: float)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

var kill_count: int = 0
var boost_time_remaining: float = 0.0

## What Player.gd multiplies its shot damage by. 1.0 normally, 1.2 while
## boosted. Read, never written, by Player.gd.
var damage_multiplier: float = 1.0:
	get:
		return 1.0 + (POWERUP_DAMAGE_BONUS if is_boosted else 0.0)

var is_boosted: bool:
	get:
		return boost_time_remaining > 0.0


func _process(delta: float) -> void:
	if boost_time_remaining <= 0.0:
		return
	boost_time_remaining = maxf(0.0, boost_time_remaining - delta)
	boost_time_changed.emit(boost_time_remaining, POWERUP_DURATION)
	if boost_time_remaining <= 0.0:
		boost_ended.emit()


## Energy for one kill, before the environmental doubling.
func energy_for(enemy_type: String) -> int:
	match enemy_type:
		"elite":
			return ENERGY_ELITE
		"boss":
			return ENERGY_BOSS
		_:
			return ENERGY_STANDARD


## Call this from Enemy.gd when an enemy dies.
##
## `killed_by` is the GDD's "killed-by source" - "barrel", "trap" or
## "player". Enemy.gd already tracks it as a field.
func register_kill(enemy_type: String, killed_by: String,
		at: Vector2) -> void:
	var environmental := killed_by in ["barrel", "trap"]
	var energy := energy_for(enemy_type)
	if environmental:
		energy *= ENVIRONMENTAL_ENERGY_MULTIPLIER

	energy_awarded.emit(energy, environmental)

	# PREVIEW(Jarman): "Combat Rewards adds kill energy to Daryl's Graze
	# Meter, a second way to charge Shockwave." add_meter caps at 100.
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.player):
		var meter := gm.player.get_node_or_null("GrazeMeter")
		if meter:
			meter.add_meter(energy)

	# "still counts toward the every-5th-kill power-up" - so this runs for
	# environmental kills too, which is why it sits outside the branch above.
	kill_count += 1
	if kill_count % KILLS_PER_POWERUP == 0:
		powerup_dropped.emit(at)
		_drop_powerup(at)


## "Stacking: Does not stack; a new pickup resets the timer to 10 s"
func start_boost() -> void:
	var was_boosted := is_boosted
	boost_time_remaining = POWERUP_DURATION
	if not was_boosted:
		boost_started.emit(POWERUP_DURATION)
	boost_time_changed.emit(boost_time_remaining, POWERUP_DURATION)


## GDD, Win and lose: "HP, Graze Meter and damage boost reset; nothing carries
## over between runs."
func reset_for_new_run() -> void:
	kill_count = 0
	if is_boosted:
		boost_time_remaining = 0.0
		boost_ended.emit()


# --------------------------------------------------------------------------
# The drop - built
# --------------------------------------------------------------------------

## Loaded lazily rather than preloaded. This is an autoload, so a preload
## would run before the project has finished importing textures on a fresh
## clone, and a missing texture would take the whole singleton down with it.
const POWERUP_SCENE_PATH := "res://scenes/PowerUp.tscn"
var _powerup_scene: PackedScene


func _drop_powerup(at: Vector2) -> void:
	if _powerup_scene == null:
		if not ResourceLoader.exists(POWERUP_SCENE_PATH):
			push_warning("CombatRewards: %s missing; no power-up dropped."
					% POWERUP_SCENE_PATH)
			return
		_powerup_scene = load(POWERUP_SCENE_PATH)

	var pickup := _powerup_scene.instantiate()
	pickup.global_position = at

	# Drop it into the room's Objects node when there is one, so it is
	# y-sorted with the other props and cleaned up with the room.
	var parent: Node = get_tree().current_scene
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.room):
		var objects := gm.room.get_node_or_null("Objects")
		if objects:
			parent = objects
	# Deferred: a kill usually lands inside a physics callback (a bullet or a
	# trap touching the enemy), and an Area2D cannot join the tree then.
	parent.add_child.call_deferred(pickup)
