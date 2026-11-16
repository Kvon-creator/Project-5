class_name GrazeMeter
extends Node2D
## Mechanic 3: Bullet Grazing.
##
## OWNER: Daryl Watkins-Mattocks. Due Nov 18.
## GDD architecture box: "GrazeMeter.gd / child of Player.tscn / Bullet
## Grazing: meter 0-100, grazed bullet IDs".
## Reads: EnemyBullet, Player ("Grazed flag and distance; hits taken (-25)").
##
## GDD input: "WASD to move close to enemy bullets without being hit."
##
## A bullet becomes a graze candidate when it enters the player's 20 px graze
## band. Credit is awarded only when it exits that band without hitting the
## player. This keeps direct hits from paying +5 before applying the -25 hit
## penalty.

# --------------------------------------------------------------------------
# GDD numbers - section 3, Bullet Grazing
# --------------------------------------------------------------------------

## "Bullet passes within 20 px of the player hitbox without hitting"
const GRAZE_DISTANCE_PX: float = 20.0
## "Meter gain per graze +5"
const METER_GAIN_PER_GRAZE: int = 5
## "Graze Meter maximum 100 (20 grazes without damage fills it)"
const METER_MAX: int = 100
## "Taking damage -25 meter"
const DAMAGE_PENALTY: int = 25

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal meter_changed(value: int, max_value: int)
## Fires the moment the meter reaches METER_MAX. Shockwave.gd listens for this
## to arm itself; the HUD listens to pulse the bar.
signal meter_full
## Fires when the meter leaves full (spent, or lost to damage).
signal meter_no_longer_full
signal grazed(bullet_position: Vector2)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

var meter: int = 0

## "Repeat grazes: Each bullet can be grazed once."
##
## Keyed by the bullet's instance id, so a bullet that lingers in the graze
## ring across many frames still only ever pays out once. Cleared on room
## change, because instance ids are not reused but the dictionary would
## otherwise grow for the whole run.
var grazed_bullet_ids: Dictionary = {}

## Bullets currently inside the graze band that have not hit the player.
## Keyed by instance id so cancellation still works while a bullet is being
## queued for deletion after a hit.
var pending_graze_ids: Dictionary = {}

@onready var player: Player = get_parent() as Player
## GrazeMeter is a child of Player, so its _ready() runs before Player._ready().
## Resolve the sibling directly instead of reading Player.graze_area, whose
## parent-level @onready assignment is not guaranteed to have run yet.
@onready var graze_area: Area2D = get_parent().get_node("GrazeArea") as Area2D


func _ready() -> void:
	# Built: taking damage costs 25 meter. Wired here rather than left as a
	# TODO because it is a cross-script link - Player emits, GrazeMeter reacts -
	# and getting that wiring right is the scaffold's job.
	if player:
		player.took_damage.connect(_on_player_took_damage)
		# The GrazeArea is exactly hitbox + 20 px. Entry starts a candidate;
		# safe exit confirms it.
		if is_instance_valid(graze_area):
			graze_area.area_entered.connect(_on_graze_area_entered)
			graze_area.area_exited.connect(_on_graze_area_exited)
	meter_changed.emit(meter, METER_MAX)


func _on_graze_area_entered(area: Area2D) -> void:
	if not (area is EnemyBullet):
		return
	var bullet := area as EnemyBullet
	var id := bullet.get_instance_id()
	if bullet.grazed or grazed_bullet_ids.has(id) or pending_graze_ids.has(id):
		return

	pending_graze_ids[id] = true
	# EnemyBullet emits before Player.take_damage(), so a direct hit cancels
	# the candidate before the damage penalty is applied.
	bullet.hit_player.connect(_on_pending_bullet_hit.bind(id), CONNECT_ONE_SHOT)
	# A bullet that expires or is destroyed while still inside the band did not
	# safely pass through it and must not award credit.
	bullet.tree_exiting.connect(_on_pending_bullet_removed.bind(id), CONNECT_ONE_SHOT)


func _on_graze_area_exited(area: Area2D) -> void:
	if not (area is EnemyBullet):
		return
	var bullet := area as EnemyBullet
	var id := bullet.get_instance_id()
	if not pending_graze_ids.has(id):
		return
	pending_graze_ids.erase(id)
	# Shockwave or lifetime cleanup can remove a bullet while it overlaps the
	# graze band. Removal is not a safe pass and must not pay out.
	if bullet.is_queued_for_deletion():
		return
	register_graze(bullet)


func _on_pending_bullet_hit(_damage: int, id: int) -> void:
	pending_graze_ids.erase(id)


func _on_pending_bullet_removed(id: int) -> void:
	pending_graze_ids.erase(id)


## Call when a bullet has safely exited the graze band. Handles bookkeeping,
## meter gain, feedback and signals.
func register_graze(bullet: Node2D) -> void:
	var id := bullet.get_instance_id()
	if grazed_bullet_ids.has(id):
		return
	grazed_bullet_ids[id] = true

	# Mark the bullet too, so other systems can see it was already grazed.
	if "grazed" in bullet:
		bullet.set("grazed", true)

	add_meter(METER_GAIN_PER_GRAZE)
	grazed.emit(bullet.global_position)
	_spawn_graze_spark(bullet.global_position)


func add_meter(amount: int) -> void:
	var was_full := meter >= METER_MAX
	meter = clampi(meter + amount, 0, METER_MAX)
	meter_changed.emit(meter, METER_MAX)

	var is_full := meter >= METER_MAX
	if is_full and not was_full:
		meter_full.emit()
	elif was_full and not is_full:
		meter_no_longer_full.emit()


func spend_all() -> void:
	## GDD, Shockwave: "Cost: All 100 meter points". And the cross-link:
	## "Firing empties the meter to 0 ... so the player has to move back into
	## fire to graze again."
	add_meter(-METER_MAX)


func _on_player_took_damage(_amount: int) -> void:
	add_meter(-DAMAGE_PENALTY)


## Clear the per-bullet record. GameManager/RoomManager should call this on
## room change so the dictionary does not grow across a whole run.
func reset_for_new_room() -> void:
	grazed_bullet_ids.clear()
	pending_graze_ids.clear()


# --------------------------------------------------------------------------
# Visuals - built
# --------------------------------------------------------------------------

## A graze spark in Graze Gold, per the GDD palette table
## ("Graze Gold: Graze Meter, graze sparks, Shockwave ring").
##
## Deliberately small and short. The avoid list bans effects "that hide
## bullets or the player hitbox", and the graze ring is exactly where the
## player most needs to see what is happening.
func _spawn_graze_spark(at: Vector2) -> void:
	var spark := Line2D.new()
	spark.width = 2.0
	spark.default_color = Palette.GRAZE_SPARK
	spark.z_index = 5
	var r := 7.0
	for i in range(9):
		var a := TAU * float(i) / 8.0
		spark.add_point(Vector2(cos(a), sin(a)) * r)
	get_tree().current_scene.add_child(spark)
	spark.global_position = at

	var tween := spark.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spark, "scale", Vector2(2.0, 2.0), 0.22)
	tween.tween_property(spark, "modulate:a", 0.0, 0.22)
	tween.chain().tween_callback(spark.queue_free)
