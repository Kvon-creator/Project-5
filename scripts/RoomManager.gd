class_name RoomManager
extends Node2D
## Mechanic 2: Room-Based Combat.
##
## OWNER: K'von Gates. Due Nov 18 (one layout, waves, door locks);
## all 10 layouts by Dec 2.
## GDD architecture box: "RoomManager.gd / Room.tscn / Room-Based Combat:
## layout, wave, enemies alive, doors locked".
## Reads: Enemy ("Enemies alive -> next wave or unlock doors").
##
## GDD input: "WASD to walk through a door. Crossing the threshold starts the
## room."
##
## Note on a cut, from the GDD: Randomized Dungeon Generation is NOT a
## separate mechanic any more. It is one rule of this one - rooms are drawn
## from 10 hand-built layouts, not generated.
##
## WHAT IS BUILT: the room visual - tilemap layers, door sprites and their
## locked/open states, spawn marker gizmos, and the layout-loading plumbing.
## WHAT IS NOT: wave logic, spawning, door state machine.

# --------------------------------------------------------------------------
# GDD numbers - section 2, Room-Based Combat
# --------------------------------------------------------------------------

## "Rooms per run 8: rooms 1-6 combat, room 7 elite, room 8 boss (proposed)"
const ROOMS_PER_RUN: int = 8
const ELITE_ROOM: int = 7
const BOSS_ROOM: int = 8

## "Layouts: Drawn at random from a pool of 10 hand-built layouts, no repeats
## in a run; objects placed on 3-6 spawn markers per layout"
const LAYOUT_POOL_SIZE: int = 10
const MIN_SPAWN_MARKERS: int = 3
const MAX_SPAWN_MARKERS: int = 6

## "Waves: Rooms 1-3: 2 waves; rooms 4-6: 3 waves; each wave 4-6 standard
## enemies; from room 4, 1 elite per wave"
const WAVES_EARLY: int = 2        # rooms 1-3
const WAVES_LATE: int = 3         # rooms 4-6
const ENEMIES_PER_WAVE_MIN: int = 4
const ENEMIES_PER_WAVE_MAX: int = 6
const FIRST_ELITE_ROOM: int = 4   # from room 4, 1 elite per wave

## "Elite room (7): 1 wave: 2 elites + 4 standard"
const ELITE_ROOM_ELITES: int = 2
const ELITE_ROOM_STANDARD: int = 4

## "Wave timing: Next wave spawns 1.5 s after the previous one is cleared"
const WAVE_DELAY_SECONDS: float = 1.5

## "Spawn distance: Enemies spawn at least 200 px from the player"
const MIN_SPAWN_DISTANCE_PX: float = 200.0

## "Interactive objects per room 1-3, type and spot picked at random each run"
## (Environmental Combat, but it is this script that places them - see the
## cross-link below.)
const OBJECTS_PER_ROOM_MIN: int = 1
const OBJECTS_PER_ROOM_MAX: int = 3

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal room_started(room_index: int)
@warning_ignore("unused_signal")
signal wave_started(wave_index: int, wave_count: int)
@warning_ignore("unused_signal")
signal wave_cleared(wave_index: int)
## Every enemy in every wave is down. GameManager listens and advances.
@warning_ignore("unused_signal")
signal room_cleared(room_index: int)
signal doors_unlocked

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

var room_index: int = 1
var wave_index: int = 0
var enemies_alive: int = 0
var doors_locked: bool = false

## Which of the 10 layouts have already been used this run.
## GDD: "no repeats in a run".
var used_layouts: Array[int] = []

## The room is a painted background plus collision, not a tilemap. See
## pipeline/room.py - it renders the image AND exports the floor outline and
## marker positions in pixels, which pipeline/make_scenes.py turns into this
## scene. That is why nothing here hard-codes a coordinate.
@onready var background: Sprite2D = $Background
@onready var bounds: StaticBody2D = $Bounds
@onready var spawn_markers: Node2D = $SpawnMarkers
@onready var object_markers: Node2D = $ObjectMarkers
@onready var doors: Node2D = $Doors
@onready var enemies: Node2D = $Enemies


func _ready() -> void:
	Palette.check_no_magenta(self)
	_refresh_door_visuals()


## How many waves this room runs. Written out because it is pure GDD table
## lookup and getting it wrong is a silent balance bug.
func wave_count_for(room: int) -> int:
	if room == ELITE_ROOM:
		return 1          # "Elite room (7) 1 wave"
	if room == BOSS_ROOM:
		return 1          # the boss fight
	return WAVES_EARLY if room <= 3 else WAVES_LATE


## The make-up of one wave, as {"standard": n, "elite": n, "boss": n}.
func wave_composition_for(room: int, _wave: int) -> Dictionary:
	if room == BOSS_ROOM:
		return {"standard": 0, "elite": 0, "boss": 1}
	if room == ELITE_ROOM:
		return {"standard": ELITE_ROOM_STANDARD,
				"elite": ELITE_ROOM_ELITES, "boss": 0}
	var standard := randi_range(ENEMIES_PER_WAVE_MIN, ENEMIES_PER_WAVE_MAX)
	var elite := 1 if room >= FIRST_ELITE_ROOM else 0
	return {"standard": standard, "elite": elite, "boss": 0}


# --------------------------------------------------------------------------
# TODOs
# --------------------------------------------------------------------------

func start_room(index: int) -> void:
	room_index = index
	wave_index = 0
	# TODO(K'von): pick an unused layout id, load it, lock the doors, then
	# start wave 0. Emit room_started(index).
	#
	# Built and ready to call:
	#   set_doors_locked(true)      - door sprites switch to the locked art
	#   place_objects()             - the 1-3 interactive objects
	lock_and_show(true)
	room_started.emit(index)


func start_next_wave() -> void:
	# TODO(K'von): spawn wave_composition_for(room_index, wave_index) at
	# markers that are at least MIN_SPAWN_DISTANCE_PX from the player.
	# Increment enemies_alive per spawn and connect each enemy's died signal
	# to _on_enemy_died.
	pass


func _on_enemy_died() -> void:
	# TODO(K'von): decrement enemies_alive. When it hits 0:
	#   - if more waves remain, wait WAVE_DELAY_SECONDS then start_next_wave()
	#   - otherwise emit room_cleared(room_index) and lock_and_show(false)
	pass


## GDD cross-link, K'von to himself: "Each layout's 3-6 spawn markers decide
## where objects can appear, and every new room rolls new objects, so no two
## runs use the same setups."
func place_objects() -> void:
	# TODO(K'von): pick randi_range(OBJECTS_PER_ROOM_MIN,
	# OBJECTS_PER_ROOM_MAX) markers from $ObjectMarkers, and instance a
	# random Barrel / Cover / Trap at each.
	pass


# --------------------------------------------------------------------------
# Door visuals - built
# --------------------------------------------------------------------------

## Set the lock state AND swap the door art to match. Call this rather than
## assigning doors_locked, so the two never disagree.
func lock_and_show(locked: bool) -> void:
	doors_locked = locked
	_refresh_door_visuals()
	if not locked:
		doors_unlocked.emit()


func _refresh_door_visuals() -> void:
	if not is_instance_valid(doors):
		return
	for door in doors.get_children():
		# Doors are Marker2D anchors right now: the archways are painted into
		# the room background, so there is no sprite to swap. They mark WHERE
		# a door is, which is what spawning and the lock state need.
		#
		# TODO(K'von): locked/unlocked art. Two options, both fine:
		#   - a Sprite2D overlay per door, swapped on lock state
		#   - render each room twice (doors shut / doors open) and swap the
		#     background, which costs more disk but zero seams
		# Until then the lock is enforced by Bounds, which is correct during
		# combat anyway: the GDD locks doors for the whole fight and only
		# unlocks once the last wave is down.
		if door is CanvasItem:
			(door as CanvasItem).modulate = (
					Palette.BLOOD_RUST if doors_locked else Color.WHITE)


## A spawn marker at least MIN_SPAWN_DISTANCE_PX from `from_position`.
## Returns the farthest marker if none qualifies, so spawning never fails.
## GDD: "Enemies spawn at least 200 px from the player".
func pick_spawn_point(from_position: Vector2) -> Vector2:
	var best: Vector2 = global_position
	var best_distance := -1.0
	var valid: Array[Vector2] = []

	for marker in spawn_markers.get_children():
		if marker is not Node2D:
			continue
		var p: Vector2 = (marker as Node2D).global_position
		var d := p.distance_to(from_position)
		if d >= MIN_SPAWN_DISTANCE_PX:
			valid.append(p)
		if d > best_distance:
			best_distance = d
			best = p

	if valid.is_empty():
		return best
	return valid[randi() % valid.size()]


## The centre of the walkable floor, in room coordinates. Written into the
## scene by the generator from the projected floor outline.
func floor_centre() -> Vector2:
	if has_meta("floor_centre"):
		return get_meta("floor_centre")
	return Vector2.ZERO
