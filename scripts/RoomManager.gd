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

## PREVIEW(K'von): the scenes the room spawns. Standard enemies are a coin
## flip between the two standard species; the elite and boss are fixed.
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
## the room before it fills.
const FIRST_WAVE_DELAY_SECONDS: float = 0.8


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


## Show a layout. Because every room image conforms to the shared framing in
## docs/ROOM_BRIEF.md, the floor outline, doors and markers are the same for
## all of them - so this is only a texture swap. Nothing about collision or
## spawning has to change.
func load_layout(index: int, mark_used: bool = true) -> void:
	var tex := RoomLayouts.texture_for(index)
	if tex == null:
		return
	layout_index = index
	background.texture = tex
	_apply_geometry(RoomLayouts.geometry_for(index))
	if mark_used and index not in used_layouts:
		used_layouts.append(index)


## Move the collision outline, door anchors and markers to where this layout
## says they are. Rooms on the shared framing all give the same answer, so
## for them this is a no-op in effect; a painted room with its own floor
## shape gets its own geometry without any engine work.
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
# TODOs
# --------------------------------------------------------------------------

func start_room(index: int) -> void:
	room_index = index
	wave_index = 0
	enemies_alive = 0
	# PREVIEW(K'von): the simplest version of the GDD loop. Pick a layout,
	# lock up, scatter objects, and start wave 0 after a short beat. Replace
	# freely; the constants above are the balance, this is just the order.
	for child in enemies.get_children():
		enemies.remove_child(child)
		child.queue_free()
	for child in objects.get_children():
		objects.remove_child(child)
		child.queue_free()
	if index == BOSS_ROOM and RoomLayouts.boss_layout() >= 0:
		load_layout(RoomLayouts.boss_layout())
	elif index == ELITE_ROOM and RoomLayouts.tagged_layout("elite") >= 0:
		load_layout(RoomLayouts.tagged_layout("elite"))
	else:
		load_unused_layout()
	lock_and_show(true)
	place_objects()
	bake_navigation.call_deferred()   # objects must be in the tree first
	room_started.emit(index)
	get_tree().create_timer(FIRST_WAVE_DELAY_SECONDS).timeout.connect(start_next_wave)


func start_next_wave() -> void:
	# PREVIEW(K'von): spawn the GDD composition at markers >= 200 px from the
	# player, one marker per enemy where possible.
	var comp := wave_composition_for(room_index, wave_index)
	var species_list: Array[String] = []
	var hare_chance := HARE_CHANCE_MID
	if room_index <= 2:
		hare_chance = HARE_CHANCE_EARLY
	elif room_index == ELITE_ROOM:
		hare_chance = HARE_CHANCE_ELITE
	for i in int(comp.get("standard", 0)):
		species_list.append("hare" if randf() < hare_chance else "snail")
	for i in int(comp.get("elite", 0)):
		species_list.append(ELITE_SPECIES)
	for i in int(comp.get("boss", 0)):
		species_list.append(BOSS_SPECIES)

	var from := Vector2.ZERO
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.player):
		from = gm.player.global_position
	var points := _spawn_points_far_from(from)
	for i in species_list.size():
		var at: Vector2 = points[i % points.size()]
		if i >= points.size():   # more enemies than markers: fan out a little
			at += Vector2(randf_range(-40, 40), randf_range(-30, 30))
		if species_list[i] == BOSS_SPECIES and spawn_markers.get_child_count() > 0:
			at = (spawn_markers.get_child(0) as Node2D).global_position   # the boss gets the stage
		_spawn_enemy(species_list[i], at)

	wave_started.emit(wave_index, wave_count_for(room_index))


func _spawn_enemy(species: String, at: Vector2) -> void:
	var e := ENEMY_SCENE.instantiate() as Enemy
	e.species = species
	e.global_position = at
	e.died.connect(_on_enemy_died)
	enemies.add_child(e)
	enemies_alive += 1
	if species == BOSS_SPECIES:
		boss_spawned.emit(e)


## Spawn markers at least MIN_SPAWN_DISTANCE_PX from `from`, shuffled; the
## farthest few if none qualify, so spawning never fails.
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
		all_points.sort_custom(func(a: Vector2, b: Vector2) -> bool:
			return a.distance_to(from) > b.distance_to(from))
		far = all_points.slice(0, maxi(1, all_points.size() / 2))
	if far.is_empty():
		far.append(floor_centre())
	far.shuffle()
	return far


func _on_enemy_died(enemy: Enemy = null) -> void:
	# PREVIEW(K'von): count down; next wave after the GDD delay, or unlock.
	enemies_alive = maxi(0, enemies_alive - 1)
	# The boss's summoned minions die with it, so the win is not held up
	# by a stray hare.
	if enemy and enemy.species == BOSS_SPECIES:
		for other in get_tree().get_nodes_in_group("enemy"):
			if other != enemy and other is Enemy:
				(other as Enemy).die()
	if enemies_alive > 0:
		return
	wave_cleared.emit(wave_index)
	wave_index += 1
	if wave_index < wave_count_for(room_index):
		get_tree().create_timer(WAVE_DELAY_SECONDS).timeout.connect(start_next_wave)
	else:
		lock_and_show(false)
		room_cleared.emit(room_index)


## GDD cross-link, K'von to himself: "Each layout's 3-6 spawn markers decide
## where objects can appear, and every new room rolls new objects, so no two
## runs use the same setups."
func place_objects() -> void:
	# PREVIEW(K'von): 1-3 distinct markers, a random object kind at each.
	var spots: Array[Vector2] = []
	for marker in object_markers.get_children():
		if marker is Node2D:
			spots.append((marker as Node2D).global_position)
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
		if e.kind == EnvObject.Kind.COVER and e.hits_taken >= EnvObject.COVER_HITS_TO_BREAK:
			continue
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
		var shape_node := wall.get_node_or_null("Shape") as CollisionShape2D
		var half := Vector2(23, 15)
		if shape_node and shape_node.shape is RectangleShape2D:
			half = (shape_node.shape as RectangleShape2D).size * 0.5
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


## The door anchor closest to `from`, as {"name": String, "position": Vector2}.
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
	if door_name.begins_with("DoorWest"):
		return Vector2(right - 90.0, c.y)
	if door_name.begins_with("DoorEast"):
		return Vector2(left + 90.0, c.y)
	return c


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
		if not (marker is Node2D):
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
