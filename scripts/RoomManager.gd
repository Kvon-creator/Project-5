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
## WHAT IS BUILT: everything in GDD section 2.
##   Run shape  - 8 rooms: 1-6 combat, 7 elite, 8 boss. Rooms 1-6 draw a
##                layout from the pool with no repeats.
##   Doors      - lock on entry, unlock when the last wave is down; walking
##                into an open door emits `door_crossed` and GameManager
##                starts the next room.
##   Waves      - the GDD table (2 or 3 waves, 4-6 standard, an elite per
##                wave from room 4; 2 elites + 4 standard in room 7), the
##                next wave 1.5 s after the last one is cleared, every enemy
##                at least 200 px from the player.
##   Objects    - 1-3 per room, kind and marker rolled fresh every room.
## The +10 HP room-clear heal lives in GameManager, off `room_cleared`.

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
signal wave_started(wave_index: int, wave_count: int)
signal wave_cleared(wave_index: int)
## Every enemy in every wave is down. GameManager listens and advances.
signal room_cleared(room_index: int)
signal doors_unlocked
## The player walked into an open door. GameManager starts the next room.
signal door_crossed(door_name: String)
## The boss has been placed; the HUD puts up its bar.
signal boss_spawned(boss: Enemy)

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

## The layout currently shown, as an index into RoomLayouts.all().
var layout_index: int = -1

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
@onready var objects: Node2D = $Objects
@onready var nav_region: NavigationRegion2D = $NavRegion
## Fixed tome walls that shape a layout. Created on demand so Room.tscn
## needs no change.
var fixtures: Node2D
var layout_title: String = ""

## Enemy Adaptation reads this mesh: the floor outline minus every piece of
## cover and every barrel, grown by the enemy radius. Rebaked whenever an
## object breaks or blows up, so a cleared lane opens for the enemies too.
const NAV_AGENT_RADIUS: float = 14.0
var _floor_polygon: PackedVector2Array = PackedVector2Array()

## Standard enemies are a mix of the two standard species; the elite and
## boss species are fixed.
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const OBJECT_SCENES: Array[PackedScene] = [
	preload("res://scenes/Barrel.tscn"),
	preload("res://scenes/Cover.tscn"),
	preload("res://scenes/Trap.tscn"),
]
const STANDARD_SPECIES: Array[String] = ["snail", "hare"]
## Room-by-room mix of the two standard species: early rooms lean melee so
## the first fights are about grazing a few arrows, later ones lean ranged.
const HARE_CHANCE_EARLY: float = 0.3     # rooms 1-2
const HARE_CHANCE_MID: float = 0.5       # rooms 3-6
const HARE_CHANCE_ELITE: float = 0.75    # room 7
const FIXTURE_SCENE: PackedScene = preload("res://scenes/Fixture.tscn")
const ELITE_SPECIES := "grotesque"
const BOSS_SPECIES := "scribe"
## A beat between the doors locking and the first wave, so the player sees
## the room before it fills. Not a GDD number; the 1.5 s rule is between
## waves.
const FIRST_WAVE_DELAY_SECONDS: float = 0.8

## How close to a door anchor counts as being in the doorway, and how
## squarely the player has to be walking into it (dot of the move input with
## the door's outward direction).
const DOOR_TRIGGER_PX: float = 52.0
const DOOR_WALK_DOT: float = 0.25

## Objects are not placed on top of the spot the player walks in at, and
## nothing spawns hard against a wall or prop.
const ENTRY_CLEARANCE_PX: float = 72.0
const SPAWN_CLEARANCE_PX: float = 22.0
const SPAWN_SPACING_PX: float = 40.0

# --------------------------------------------------------------------------
# The room's state machine
# --------------------------------------------------------------------------

## IDLE      nothing running (before the run starts)
## STARTING  doors locked, objects placed, first wave about to spawn
## FIGHTING  a wave is alive
## BETWEEN   wave cleared, the next one spawns when the 1.5 s is up
## CLEARED   last wave down, doors open, waiting for the player to leave
## EXITED    the player has walked through a door; GameManager takes over
## STOPPED   the run is over
enum State { IDLE, STARTING, FIGHTING, BETWEEN, CLEARED, EXITED, STOPPED }

var state: State = State.IDLE
var _wave_timer: float = 0.0
var _door_pulse: float = 0.0

## Where the player stands when this room starts. Set by start_room, read by
## GameManager.
var entry_point: Vector2 = Vector2.ZERO


func _ready() -> void:
	Palette.check_no_magenta(self)
	fixtures = Node2D.new()
	fixtures.name = "Fixtures"
	fixtures.y_sort_enabled = true
	add_child(fixtures)
	_refresh_door_visuals()
	if layout_index < 0 and RoomLayouts.count() > 0:
		# Something to look at before the run starts. Not marked used, or
		# start_room would skip the first painted room.
		load_layout(0, false)


## Show a layout: its painted background, floor outline, doors, markers and
## fixed tome walls.
func load_layout(index: int, mark_used: bool = true) -> void:
	var tex := RoomLayouts.texture_for(index)
	if tex == null:
		return
	layout_index = index
	background.texture = tex
	var g := RoomLayouts.geometry_for(index)
	_apply_geometry(g)
	# GDD: "objects placed on 3-6 spawn markers per layout".
	var marker_count: int = (g.get("object_markers", []) as Array).size()
	if marker_count < MIN_SPAWN_MARKERS or marker_count > MAX_SPAWN_MARKERS:
		push_warning("RoomManager: layout %d has %d object markers; the GDD asks for %d-%d."
				% [index, marker_count, MIN_SPAWN_MARKERS, MAX_SPAWN_MARKERS])
	if mark_used and index not in used_layouts:
		used_layouts.append(index)


## Move the collision outline, door anchors and markers to where this layout
## says they are.
func _apply_geometry(g: Dictionary) -> void:
	if g.is_empty():
		return
	if g.has("floor_polygon"):
		var pts := PackedVector2Array()
		for p in g["floor_polygon"]:
			pts.append(Vector2(p[0], p[1]))
		var shape := bounds.get_node_or_null("Shape") as CollisionPolygon2D
		if shape:
			shape.polygon = pts
		_floor_polygon = pts
	if g.has("floor_centre"):
		set_meta("floor_centre", Vector2(g["floor_centre"][0], g["floor_centre"][1]))
	if g.has("doors"):
		_sync_markers(doors, "Door", g["doors"])
	if g.has("spawn_markers"):
		_sync_markers(spawn_markers, "Spawn", g["spawn_markers"])
	if g.has("object_markers"):
		_sync_markers(object_markers, "ObjSpot", g["object_markers"])
	layout_title = str(g.get("title", ""))
	if is_instance_valid(fixtures):
		for child in fixtures.get_children():
			fixtures.remove_child(child)   # out of the tree now, so a bake this frame ignores it
			child.queue_free()
		for f in g.get("fixtures", []):
			var wall := FIXTURE_SCENE.instantiate() as Node2D
			wall.global_position = Vector2(f[0], f[1])
			fixtures.add_child(wall)
	_refresh_door_visuals()


## Make `parent` hold exactly one Marker2D per entry, named prefix+key.
## `entries` is a Dictionary (doors, keyed by name) or an Array (markers).
func _sync_markers(parent: Node2D, prefix: String, entries: Variant) -> void:
	var wanted: Dictionary = {}
	if typeof(entries) == TYPE_DICTIONARY:
		for key in entries.keys():
			wanted[prefix + str(key).capitalize()] = Vector2(entries[key][0], entries[key][1])
	else:
		for i in entries.size():
			wanted[prefix + str(i)] = Vector2(entries[i][0], entries[i][1])
	for child in parent.get_children():
		if not wanted.has(child.name):
			parent.remove_child(child)   # gone now, not at the end of the frame
			child.queue_free()
	for marker_name in wanted.keys():
		var m := parent.get_node_or_null(NodePath(marker_name)) as Marker2D
		if m == null:
			m = Marker2D.new()
			m.name = marker_name
			parent.add_child(m)
		m.position = wanted[marker_name]


## Pick and show a layout not yet used this run.
## GDD: "no repeats in a run".
func load_unused_layout() -> void:
	var index := RoomLayouts.draw_unused(used_layouts)
	if index >= 0:
		load_layout(index)


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
# Running a room
# --------------------------------------------------------------------------

## Start room `index`. `via_door` is the door the player left the previous
## room through ("" for the first room of a run); they come in on the
## opposite side.
##
## GDD: "Crossing the threshold starts the room" and "Doors: Lock on entry".
func start_room(index: int, via_door: String = "") -> void:
	room_index = index
	wave_index = 0
	enemies_alive = 0

	# Nothing from the last room follows the player in.
	for child in enemies.get_children():
		enemies.remove_child(child)
		child.queue_free()
	for child in objects.get_children():
		objects.remove_child(child)
		child.queue_free()
	for group in ["enemy_bullet", "player_bullet"]:
		for bullet in get_tree().get_nodes_in_group(group):
			bullet.queue_free()

	# "Rooms per run 8: rooms 1-6 combat, room 7 elite, room 8 boss". The
	# elite court and the boss arena are fixed; rooms 1-6 draw from the rest
	# of the pool with no repeats.
	if index == BOSS_ROOM and RoomLayouts.boss_layout() >= 0:
		load_layout(RoomLayouts.boss_layout())
	elif index == ELITE_ROOM and RoomLayouts.tagged_layout("elite") >= 0:
		load_layout(RoomLayouts.tagged_layout("elite"))
	else:
		load_unused_layout()

	if via_door == "":
		entry_point = _nearest_open_point(floor_centre() + Vector2(0, 70))
	else:
		entry_point = _nearest_open_point(entry_point_opposite(via_door))

	lock_and_show(true)
	place_objects()
	bake_navigation.call_deferred()   # objects must be in the tree first
	state = State.STARTING
	_wave_timer = FIRST_WAVE_DELAY_SECONDS
	room_started.emit(index)


## The run is over (won or lost): no more waves, doors stay as they are.
func stop() -> void:
	state = State.STOPPED


func _physics_process(delta: float) -> void:
	match state:
		State.STARTING, State.BETWEEN:
			_wave_timer -= delta
			if _wave_timer <= 0.0:
				start_next_wave()
		State.CLEARED:
			_check_doors()
			_door_pulse += delta
			_pulse_open_doors()


## Spawn wave `wave_index`: the GDD composition, every enemy at least 200 px
## from the player.
func start_next_wave() -> void:
	state = State.FIGHTING
	var comp := wave_composition_for(room_index, wave_index)
	var hare_chance := HARE_CHANCE_MID
	if room_index <= 2:
		hare_chance = HARE_CHANCE_EARLY
	elif room_index == ELITE_ROOM:
		hare_chance = HARE_CHANCE_ELITE
	# Elites first, so they get real spawn markers when a wave has more
	# enemies than the layout has markers.
	var species_list: Array[String] = []
	for i in int(comp.get("boss", 0)):
		species_list.append(BOSS_SPECIES)
	for i in int(comp.get("elite", 0)):
		species_list.append(ELITE_SPECIES)
	for i in int(comp.get("standard", 0)):
		species_list.append("hare" if randf() < hare_chance else "snail")

	var from := _player_position()
	var points := spawn_points_for(species_list.size(), from)
	for i in species_list.size():
		var at: Vector2 = points[i]
		if species_list[i] == BOSS_SPECIES:
			at = _boss_spawn_point(from)
		_spawn_enemy(species_list[i], at)

	wave_started.emit(wave_index, wave_count_for(room_index))
	if enemies_alive == 0:
		_finish_wave()   # an empty wave is a cleared wave


func _spawn_enemy(species: String, at: Vector2) -> void:
	var e := ENEMY_SCENE.instantiate() as Enemy
	e.species = species
	e.global_position = at
	e.died.connect(_on_enemy_died)
	enemies.add_child(e)
	enemies_alive += 1
	if species == BOSS_SPECIES:
		boss_spawned.emit(e)


## `count` places to spawn, every one at least MIN_SPAWN_DISTANCE_PX from
## `from`. GDD: "Enemies spawn at least 200 px from the player".
##
## The layout's spawn markers come first. A wave can be bigger than the
## number of markers far enough away (up to 7 enemies, 6 markers, and the
## player may be standing on one), so the rest are open floor points that
## pass the same distance rule.
func spawn_points_for(count: int, from: Vector2) -> Array[Vector2]:
	var markers := _spawn_points_far_from(from)
	var out: Array[Vector2] = []
	for p in markers:
		if out.size() >= count:
			break
		out.append(p)
	var tries := 0
	while out.size() < count and tries < 300:
		tries += 1
		var p := _random_floor_point()
		if p.distance_to(from) < MIN_SPAWN_DISTANCE_PX:
			continue
		if not _is_open_floor(p, SPAWN_CLEARANCE_PX):
			continue
		var crowded := false
		for q in out:
			if q.distance_to(p) < SPAWN_SPACING_PX:
				crowded = true
				break
		if not crowded:
			out.append(p)
	# No more open floor that far away: share the markers. Enemies shoulder
	# each other apart on their own.
	var i := 0
	while out.size() < count:
		out.append(markers[i % markers.size()])
		i += 1
	return out


## Spawn markers at least MIN_SPAWN_DISTANCE_PX from `from`, shuffled. Never
## empty: with no marker far enough it falls back to open floor that is,
## and only then to the farthest marker.
func _spawn_points_far_from(from: Vector2) -> Array[Vector2]:
	var all_points: Array[Vector2] = []
	for marker in spawn_markers.get_children():
		if marker is Node2D:
			all_points.append((marker as Node2D).global_position)
	var far: Array[Vector2] = []
	for p in all_points:
		if p.distance_to(from) >= MIN_SPAWN_DISTANCE_PX:
			far.append(p)
	if far.is_empty():
		for i in 200:
			var p := _random_floor_point()
			if p.distance_to(from) >= MIN_SPAWN_DISTANCE_PX \
					and _is_open_floor(p, SPAWN_CLEARANCE_PX):
				far.append(p)
				if far.size() >= 4:
					break
	if far.is_empty() and not all_points.is_empty():
		all_points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.distance_to(from) > b.distance_to(from))
		far.append(all_points[0])
	if far.is_empty():
		far.append(floor_centre())
	far.shuffle()
	return far


## The boss takes the stage (the layout's first spawn marker) unless the
## player is standing too close to it.
func _boss_spawn_point(from: Vector2) -> Vector2:
	if spawn_markers.get_child_count() > 0:
		var stage: Vector2 = (spawn_markers.get_child(0) as Node2D).global_position
		if stage.distance_to(from) >= MIN_SPAWN_DISTANCE_PX:
			return stage
	return _spawn_points_far_from(from)[0]


func _on_enemy_died(enemy: Enemy = null) -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	# The boss's summoned minions die with it, so the win is not held up
	# by a stray hare. Each of those deaths comes back through here.
	if enemy and enemy.species == BOSS_SPECIES:
		for other in get_tree().get_nodes_in_group("enemy"):
			if other != enemy and other is Enemy:
				(other as Enemy).die()
	if enemies_alive > 0 or state != State.FIGHTING:
		return
	_finish_wave()


## The last enemy of a wave is down.
## GDD: "Next wave spawns 1.5 s after the previous one is cleared" and
## "Doors ... unlock when the last wave is defeated".
func _finish_wave() -> void:
	wave_cleared.emit(wave_index)
	wave_index += 1
	if wave_index < wave_count_for(room_index):
		state = State.BETWEEN
		_wave_timer = WAVE_DELAY_SECONDS
	else:
		state = State.CLEARED
		_door_pulse = 0.0
		lock_and_show(false)
		room_cleared.emit(room_index)


## GDD: "Interactive objects per room 1-3, type and spot picked at random
## each run", and the cross-link, K'von to himself: "Each layout's 3-6 spawn
## markers decide where objects can appear, and every new room rolls new
## objects, so no two runs use the same setups."
func place_objects() -> void:
	var spots: Array[Vector2] = []
	var fallback: Array[Vector2] = []
	for marker in object_markers.get_children():
		if not (marker is Node2D):
			continue
		var p: Vector2 = (marker as Node2D).global_position
		if _inside_fixture(p, 8.0):
			continue   # a tome wall already stands on this marker
		fallback.append(p)
		# Not under the player's feet as they walk in.
		if p.distance_to(entry_point) >= ENTRY_CLEARANCE_PX:
			spots.append(p)
	if spots.is_empty():
		spots = fallback
	spots.shuffle()
	var count := mini(randi_range(OBJECTS_PER_ROOM_MIN, OBJECTS_PER_ROOM_MAX), spots.size())
	for i in count:
		var obj := OBJECT_SCENES[randi() % OBJECT_SCENES.size()].instantiate() as Node2D
		obj.global_position = spots[i]
		objects.add_child(obj)
		# a broken tome stack or a spent barrel is no longer an obstacle
		if obj.has_signal("broke"):
			obj.broke.connect(func(_at: Vector2) -> void: bake_navigation.call_deferred())
		if obj.has_signal("detonated"):
			obj.detonated.connect(func(_at: Vector2, _r: float) -> void: bake_navigation.call_deferred())
		# an armed trap is routed around; a disarmed plate is just floor
		if obj.has_signal("armed_changed"):
			obj.armed_changed.connect(func(_armed: bool) -> void: bake_navigation.call_deferred())


# --------------------------------------------------------------------------
# Floor queries
# --------------------------------------------------------------------------

func _player() -> Player:
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.player):
		return gm.player
	return null


func _player_position() -> Vector2:
	var p := _player()
	return p.global_position if p else entry_point


## A uniformly random point in the floor's bounding box (not necessarily on
## the floor - callers test it).
func _random_floor_point() -> Vector2:
	if _floor_polygon.size() < 3:
		return floor_centre()
	var lo := _floor_polygon[0]
	var hi := _floor_polygon[0]
	for p in _floor_polygon:
		lo = lo.min(p)
		hi = hi.max(p)
	return Vector2(randf_range(lo.x, hi.x), randf_range(lo.y, hi.y))


## Is `p` on the floor, at least `margin` px from the walls, the fixed tome
## walls and every object (armed traps get their 75 px hazard clearance)?
func _is_open_floor(p: Vector2, margin: float) -> bool:
	var n := _floor_polygon.size()
	if n >= 3:
		if not Geometry2D.is_point_in_polygon(p, _floor_polygon):
			return false
		for i in n:
			var a := _floor_polygon[i]
			var b := _floor_polygon[(i + 1) % n]
			if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) < margin:
				return false
	if _inside_fixture(p, margin):
		return false
	for obj in objects.get_children():
		if not (obj is EnvObject) or obj.is_queued_for_deletion():
			continue
		var e := obj as EnvObject
		if e.is_spent():
			continue
		var half := _obstacle_half_size(e) + Vector2.ONE * margin
		if e.kind == EnvObject.Kind.TRAP:
			half += Vector2.ONE * Enemy.HAZARD_AVOID_PX
		var d := (p - e.global_position).abs()
		if d.x <= half.x and d.y <= half.y:
			return false
	return true


## Is `p` within `margin` px of a fixed tome wall?
func _inside_fixture(p: Vector2, margin: float) -> bool:
	if not is_instance_valid(fixtures):
		return false
	for wall in fixtures.get_children():
		if not (wall is Node2D) or wall.is_queued_for_deletion():
			continue
		var half := _fixture_half_size(wall) + Vector2.ONE * margin
		var d := (p - (wall as Node2D).global_position).abs()
		if d.x <= half.x and d.y <= half.y:
			return true
	return false


func _fixture_half_size(wall: Node) -> Vector2:
	var shape_node := wall.get_node_or_null("Shape") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		return (shape_node.shape as RectangleShape2D).size * 0.5
	return Vector2(23, 15)


## `p` itself if the player can stand there, otherwise the closest point
## around it that they can. Used for the spot the player walks in at.
func _nearest_open_point(p: Vector2) -> Vector2:
	const CLEARANCE := 14.0
	if _is_open_floor(p, CLEARANCE):
		return p
	for ring in range(1, 16):
		var r := ring * 16.0
		for step in 16:
			var q := p + Vector2.from_angle(TAU * step / 16.0) * r
			if _is_open_floor(q, CLEARANCE):
				return q
	return p


## Build the navigation mesh for the current floor and objects.
## GDD, Enemy Adaptation: "Routes around walls and destructible cover while
## chasing the player". Walls are the floor outline; cover, barrels and
## armed traps are cut out as obstructions.
func bake_navigation() -> void:
	if not is_instance_valid(nav_region) or _floor_polygon.size() < 3:
		return
	var src := NavigationMeshSourceGeometryData2D.new()
	src.add_traversable_outline(_floor_polygon)
	for obj in get_tree().get_nodes_in_group("env_object"):
		if not (obj is EnvObject) or not is_instance_valid(obj) or obj.is_queued_for_deletion():
			continue
		var e := obj as EnvObject
		if e.is_spent():
			continue   # a broken stack or a blown barrel is just floor
		var half := _obstacle_half_size(e)
		if e.kind == EnvObject.Kind.TRAP:
			if not e.trap_armed:
				continue   # a disarmed plate is just floor
			# GDD: "Steers clear of active hazards within 75 px" - the mesh
			# keeps paths that far from an armed plate's edge.
			half += Vector2.ONE * (Enemy.HAZARD_AVOID_PX - NAV_AGENT_RADIUS)
		var c := e.global_position
		src.add_obstruction_outline(PackedVector2Array([
			c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
			c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)]))
	for wall in get_tree().get_nodes_in_group("fixture"):
		if not (wall is Node2D) or wall.is_queued_for_deletion():
			continue
		var half := _fixture_half_size(wall)
		var c: Vector2 = (wall as Node2D).global_position
		src.add_obstruction_outline(PackedVector2Array([
			c + Vector2(-half.x, -half.y), c + Vector2(half.x, -half.y),
			c + Vector2(half.x, half.y), c + Vector2(-half.x, half.y)]))
	var navpoly := NavigationPolygon.new()
	navpoly.agent_radius = NAV_AGENT_RADIUS
	NavigationServer2D.bake_from_source_geometry_data(navpoly, src)
	nav_region.navigation_polygon = navpoly


## The footprint of an object's collision shape, as a half size.
func _obstacle_half_size(e: EnvObject) -> Vector2:
	var shape_node := e.get_node_or_null("Shape") as CollisionShape2D
	if shape_node and shape_node.shape is RectangleShape2D:
		return (shape_node.shape as RectangleShape2D).size * 0.5
	if shape_node and shape_node.shape is CircleShape2D:
		var r: float = (shape_node.shape as CircleShape2D).radius
		return Vector2(r, r)
	return Vector2(16, 12)


# --------------------------------------------------------------------------
# Doors
# --------------------------------------------------------------------------

## Set the lock state AND swap the door seals to match. Call this rather
## than assigning doors_locked, so the two never disagree.
func lock_and_show(locked: bool) -> void:
	doors_locked = locked
	_refresh_door_visuals()
	if not locked:
		doors_unlocked.emit()


## The direction that leads out of the room through `door`.
func door_outward(door: Node2D) -> Vector2:
	var door_name := String(door.name)
	if door_name.begins_with("DoorNorth"):
		return Vector2.UP
	if door_name.begins_with("DoorSouth"):
		return Vector2.DOWN
	if door_name.begins_with("DoorWest"):
		return Vector2.LEFT
	if door_name.begins_with("DoorEast"):
		return Vector2.RIGHT
	var out := door.global_position - floor_centre()
	return out.normalized() if out.length() > 0.01 else Vector2.UP


## GDD input: "WASD to walk through a door. Crossing the threshold starts
## the room." Only open doors let the player through, and only when they
## are walking into one - standing next to a door as the last enemy falls
## does not whisk them away.
func _check_doors() -> void:
	if doors_locked or room_index >= ROOMS_PER_RUN:
		return
	var player := _player()
	if player == null or player.is_dead:
		return
	var move := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if move == Vector2.ZERO:
		return
	for door in doors.get_children():
		if not (door is Node2D):
			continue
		var d := door as Node2D
		if d.global_position.distance_to(player.global_position) > DOOR_TRIGGER_PX:
			continue
		if move.dot(door_outward(d)) < DOOR_WALK_DOT:
			continue
		state = State.EXITED
		door_crossed.emit(String(d.name))
		return


## The door anchor closest to `from`, as {"name", "position", "distance"}.
func nearest_door(from: Vector2) -> Dictionary:
	var best := {"name": "", "position": Vector2.ZERO, "distance": INF}
	for door in doors.get_children():
		if not (door is Node2D):
			continue
		var d := (door as Node2D).global_position.distance_to(from)
		if d < best["distance"]:
			best = {"name": String(door.name), "position": (door as Node2D).global_position, "distance": d}
	return best


## Where the player appears after walking through `door_name`: just inside the
## opposite side of the new room, so the walk reads as continuing.
func entry_point_opposite(door_name: String) -> Vector2:
	var c := floor_centre()
	var shape := bounds.get_node_or_null("Shape") as CollisionPolygon2D
	var top := c.y - 150.0
	var bottom := c.y + 150.0
	var left := c.x - 380.0
	var right := c.x + 380.0
	if shape and shape.polygon.size() > 0:
		top = INF; bottom = -INF; left = INF; right = -INF
		for p in shape.polygon:
			top = minf(top, p.y); bottom = maxf(bottom, p.y)
			left = minf(left, p.x); right = maxf(right, p.x)
	if door_name.begins_with("DoorNorth"):
		return Vector2(c.x, bottom - 70.0)
	if door_name.begins_with("DoorSouth"):
		return Vector2(c.x, top + 70.0)
	if door_name.begins_with("DoorWest"):
		return Vector2(right - 90.0, c.y)
	if door_name.begins_with("DoorEast"):
		return Vector2(left + 90.0, c.y)
	return c


## Each door anchor carries a "Seal": a strip of light across the threshold.
## Locked, it is Blood Rust with a crossed bar; open, it is Bone and pulses.
## The archways themselves are painted into the room background, so this is
## the only part of a door that changes.
func _refresh_door_visuals() -> void:
	if not is_instance_valid(doors):
		return
	for door in doors.get_children():
		if not (door is Node2D):
			continue
		var seal := _seal_for(door as Node2D)
		var glow := seal.get_node("Glow") as Polygon2D
		var bars := seal.get_node("Bars") as Node2D
		bars.visible = doors_locked
		if doors_locked:
			glow.color = Color(Palette.BLOOD_RUST, 0.55)
		else:
			glow.color = Color(Palette.BONE, 0.75)


func _pulse_open_doors() -> void:
	var alpha := 0.6 + 0.3 * sin(_door_pulse * 5.0)
	for door in doors.get_children():
		var seal := door.get_node_or_null("Seal")
		if seal:
			(seal.get_node("Glow") as Polygon2D).color = Color(Palette.BONE, alpha)


## Find or build the seal under a door anchor.
func _seal_for(door: Node2D) -> Node2D:
	var seal := door.get_node_or_null("Seal") as Node2D
	if seal:
		return seal
	seal = Node2D.new()
	seal.name = "Seal"
	seal.z_index = -5   # over the painted room, under everything that moves
	door.add_child(seal)

	# The strip lies across the doorway: wide for a north or south door,
	# tall for a side door.
	var outward := door_outward(door)
	var side_door := absf(outward.x) > absf(outward.y)
	var radii := Vector2(11, 30) if side_door else Vector2(34, 9)

	var glow := Polygon2D.new()
	glow.name = "Glow"
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		pts.append(Vector2(cos(a) * radii.x, sin(a) * radii.y))
	glow.polygon = pts
	seal.add_child(glow)

	var bars := Node2D.new()
	bars.name = "Bars"
	seal.add_child(bars)
	for flip in [1.0, -1.0]:
		var bar := Line2D.new()
		bar.width = 3.0
		bar.default_color = Palette.INK
		bar.add_point(Vector2(-radii.x, -radii.y * flip) * 0.7)
		bar.add_point(Vector2(radii.x, radii.y * flip) * 0.7)
		bars.add_child(bar)
	return seal


## A spawn marker at least MIN_SPAWN_DISTANCE_PX from `from_position`.
## GDD: "Enemies spawn at least 200 px from the player".
func pick_spawn_point(from_position: Vector2) -> Vector2:
	return _spawn_points_far_from(from_position)[0]


## The centre of the walkable floor, in room coordinates. Written into the
## scene by the generator from the projected floor outline.
func floor_centre() -> Vector2:
	if has_meta("floor_centre"):
		return get_meta("floor_centre")
	return Vector2.ZERO
