extends Node
## Rule-by-rule check of K'von's two mechanics against the GDD. Not part of
## the game.
##
##   godot --headless --path . res://tests/MechanicsTest.tscn
##
## Plays a whole 8-room run (killing each wave outright), then sets up the
## barrel, cover and trap cases one at a time. Prints one line per rule and
## exits 0 only if every rule holds.

const TIME_SCALE := 4.0

var _main: Node
var _gm: GameManager
var _room: RoomManager
var _player: Player
var _passed: int = 0
var _failed: int = 0
var _clock: float = 0.0          # game seconds, from physics ticks

# what the signals saw
var _wave_started_at: Array[float] = []
var _wave_cleared_at: Array[float] = []
var _spawn_distances: Array[float] = []
var _energy: Array = []          # [amount, environmental]
var _won: bool = false


func _ready() -> void:
	# Fast-forward, but keep the physics step at the game's real 1/60 s.
	Engine.time_scale = TIME_SCALE
	Engine.physics_ticks_per_second = int(60 * TIME_SCALE)
	Engine.max_physics_steps_per_frame = 64
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)
	_gm = GameManager.instance
	_room = _gm.room
	_player = _gm.player
	_room.wave_started.connect(_on_wave_started)
	_room.wave_cleared.connect(func(_i: int) -> void: _wave_cleared_at.append(_clock))
	_gm.run_won.connect(func() -> void: _won = true)
	CombatRewards.energy_awarded.connect(
			func(amount: int, env: bool) -> void: _energy.append([amount, env]))
	_run.call_deferred()


func _physics_process(delta: float) -> void:
	_clock += delta


func _on_wave_started(_i: int, _n: int) -> void:
	_wave_started_at.append(_clock)
	for e in _room.enemies.get_children():
		_spawn_distances.append((e as Node2D).global_position.distance_to(_player.global_position))


func _check(rule: String, ok: bool, detail: String = "") -> void:
	if ok:
		_passed += 1
	else:
		_failed += 1
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", rule, ("  (" + detail + ")") if detail != "" else ""])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _seconds(s: float) -> void:
	var until := _clock + s
	while _clock < until:
		await get_tree().physics_frame


func _run() -> void:
	_static_layout_checks()
	_wave_table_checks()
	await _full_run()
	_finish()


# --------------------------------------------------------------------------
# Room-Based Combat: tables
# --------------------------------------------------------------------------

func _wave_table_checks() -> void:
	var counts: Array[int] = []
	for r in range(1, 9):
		counts.append(_room.wave_count_for(r))
	_check("waves per room: 2,2,2,3,3,3 then 1 elite wave and the boss",
			counts == [2, 2, 2, 3, 3, 3, 1, 1], str(counts))
	var ok := true
	for r in range(1, 7):
		for i in 40:
			var c := _room.wave_composition_for(r, 0)
			if c["standard"] < 4 or c["standard"] > 6 or c["elite"] != (1 if r >= 4 else 0) or c["boss"] != 0:
				ok = false
	_check("each wave 4-6 standard; 1 elite per wave from room 4", ok)
	var e := _room.wave_composition_for(7, 0)
	_check("elite room: 2 elites + 4 standard", e["elite"] == 2 and e["standard"] == 4 and e["boss"] == 0, str(e))
	var b := _room.wave_composition_for(8, 0)
	_check("boss room: the boss alone", b["boss"] == 1 and b["standard"] == 0 and b["elite"] == 0, str(b))
	_check("boss has 1,200 HP; elite 120; standard 40",
			Enemy.HP_BY_TIER == {"standard": 40, "elite": 120, "boss": 1200})


func _static_layout_checks() -> void:
	_check("pool of 10 layouts", RoomLayouts.count() == 10, str(RoomLayouts.count()))
	var marker_ok := true
	var door_ok := true
	var entry_ok := true
	var spawn_ok := true
	var notes: Array[String] = []
	for i in RoomLayouts.count():
		var entry := RoomLayouts.entry(i)
		var layout_name := str(entry.get("name", i))
		_room.load_layout(i, false)
		# "objects placed on 3-6 spawn markers per layout" - markers a tome
		# wall is standing on do not count.
		var usable := 0
		for m in _room.object_markers.get_children():
			if not _room._inside_fixture((m as Node2D).global_position, 8.0):
				usable += 1
		if usable < 3 or usable > 6:
			marker_ok = false
			notes.append("%s has %d usable object markers" % [layout_name, usable])
		if entry.get("boss", false):
			continue   # the boss arena has no way out; the run ends there
		if _room.doors.get_child_count() == 0:
			door_ok = false
			notes.append("%s has no doors" % layout_name)
		for door in _room.doors.get_children():
			var d := door as Node2D
			# can the knight get close enough to walk through it?
			var reach := _distance_to_floor(d.global_position) + 8.0 + 6.0
			if reach > RoomManager.DOOR_TRIGGER_PX:
				door_ok = false
				notes.append("%s %s is %.0f px from the floor" % [layout_name, d.name, reach])
			# coming in through this door's opposite: a clear spot, with
			# room for a full wave 200 px away
			var at := _room._nearest_open_point(_room.entry_point_opposite(String(d.name)))
			if not _room._is_open_floor(at, 10.0):
				entry_ok = false
				notes.append("%s entry via %s is blocked" % [layout_name, d.name])
			for p in _room.spawn_points_for(7, at):
				if p.distance_to(at) < RoomManager.MIN_SPAWN_DISTANCE_PX - 0.01 \
						or not Geometry2D.is_point_in_polygon(p, _room._floor_polygon):
					spawn_ok = false
					notes.append("%s spawn %s too close to %s or off the floor" % [layout_name, str(p), str(at)])
	_check("every layout offers 3-6 object markers", marker_ok, "; ".join(notes))
	_check("every combat layout has doors the player can reach", door_ok, "; ".join(notes))
	_check("every entry point is clear floor", entry_ok, "; ".join(notes))
	_check("a 7-enemy wave fits 200 px from every entry point", spawn_ok, "; ".join(notes))


func _distance_to_floor(p: Vector2) -> float:
	var poly := _room._floor_polygon
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	var best := INF
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		best = minf(best, q.distance_to(p))
	return best


# --------------------------------------------------------------------------
# Room-Based Combat: a whole run
# --------------------------------------------------------------------------

func _kill_all() -> void:
	for e in _room.enemies.get_children():
		if e is Enemy:
			(e as Enemy).take_damage(99999, "player")


func _release_moves() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)


func _full_run() -> void:
	# a fresh run, since the layout sweep above swapped the room around
	_gm.room.used_layouts.clear()
	_gm.start_run()
	_player.is_invulnerable = true

	var layouts_seen: Array[int] = []
	var objects_ok := true
	var waves_ok := true
	var lock_ok := true
	var heal_ok := true
	var delay_ok := true
	var delay_note := ""

	for room_number in range(1, 9):
		_check_quiet("room counter", _gm.room_index == room_number and _room.room_index == room_number)
		layouts_seen.append(_room.layout_index)
		var n_objects := 0
		for o in _room.objects.get_children():
			if o is EnvObject:
				n_objects += 1
		if n_objects < 1 or n_objects > 3:
			objects_ok = false
		if not _room.doors_locked:
			lock_ok = false          # "Doors: Lock on entry"

		if room_number == 1:
			await _locked_door_check()

		var expected_waves := _room.wave_count_for(room_number)
		_wave_started_at.clear()
		_wave_cleared_at.clear()
		_player.hp = 50
		for w in expected_waves:
			var guard := 0
			while _room.state != RoomManager.State.FIGHTING and guard < 600:
				guard += 1
				await get_tree().physics_frame
			if _room.state != RoomManager.State.FIGHTING:
				waves_ok = false
				break
			if w < expected_waves - 1 and not _room.doors_locked:
				lock_ok = false
			await _frames(3)
			_kill_all()
			await _frames(2)
		if _wave_started_at.size() != expected_waves:
			waves_ok = false
		# "Next wave spawns 1.5 s after the previous one is cleared"
		for w in range(1, _wave_started_at.size()):
			var gap := _wave_started_at[w] - _wave_cleared_at[w - 1]
			if absf(gap - RoomManager.WAVE_DELAY_SECONDS) > 0.06:
				delay_ok = false
				delay_note = "%.2f s in room %d" % [gap, room_number]
		# "unlock when the last wave is defeated", "+10 HP"
		if room_number < 8:
			if _room.doors_locked or _room.state != RoomManager.State.CLEARED:
				lock_ok = false
			if _player.hp != 60:
				heal_ok = false

		if room_number == 2:
			await _environment_checks()
		if room_number == 8:
			break
		await _walk_through_door(room_number)

	_check("rooms 1-8 each ran the GDD's wave count", waves_ok)
	_check("next wave 1.5 s after the last one is cleared", delay_ok, delay_note)
	_check("doors lock on entry and unlock when the last wave is down", lock_ok)
	_check("room clear heals +10 HP", heal_ok)
	_check("1-3 interactive objects in every room", objects_ok)
	var unique := {}
	for i in layouts_seen:
		unique[i] = true
	_check("no layout repeats in a run", unique.size() == 8, str(layouts_seen))
	_check("room 7 is the elite court, room 8 the boss arena",
			RoomLayouts.entry(layouts_seen[6]).get("elite", false)
			and RoomLayouts.entry(layouts_seen[7]).get("boss", false))
	var closest := INF
	for d in _spawn_distances:
		closest = minf(closest, d)
	_check("every enemy spawned at least 200 px from the player",
			closest >= RoomManager.MIN_SPAWN_DISTANCE_PX - 0.01,
			"%d spawns, closest %.0f px" % [_spawn_distances.size(), closest])
	await _frames(5)
	_check("beating the boss in room 8 wins the run", _won and _gm.is_run_over)
	_player.heal_room_clear()
	_check("HP is capped at 100", _player.hp <= 100)


var _quiet_failures: Dictionary = {}


## For checks made once per room: only speak up when one fails.
func _check_quiet(rule: String, ok: bool) -> void:
	if not ok and not _quiet_failures.has(rule):
		_quiet_failures[rule] = true
		_check(rule, false)


## Room 1, mid-fight: walking into a door does nothing while it is locked.
func _locked_door_check() -> void:
	var door := _room.doors.get_child(0) as Node2D
	_player.global_position = door.global_position - _room.door_outward(door) * 20.0
	_press_toward(_room.door_outward(door))
	await _frames(20)
	_release_moves()
	_check("a locked door does not let the player through", _gm.room_index == 1)


func _press_toward(dir: Vector2) -> void:
	_release_moves()
	if dir.x < -0.3:
		Input.action_press("move_left")
	if dir.x > 0.3:
		Input.action_press("move_right")
	if dir.y < -0.3:
		Input.action_press("move_up")
	if dir.y > 0.3:
		Input.action_press("move_down")


func _walk_through_door(room_number: int) -> void:
	var door := _room.doors.get_child(randi() % _room.doors.get_child_count()) as Node2D
	var outward := _room.door_outward(door)
	# start a little way back on the floor and actually walk there
	var start := _room._nearest_open_point(door.global_position - outward * 60.0)
	_player.global_position = start
	if room_number == 1:
		await _frames(20)
		_check("standing by an open door does not start the next room", _gm.room_index == 1)
	var to_door := door.global_position - start
	var guard := 0
	while _gm.room_index == room_number and guard < 240:
		guard += 1
		to_door = door.global_position - _player.global_position
		# steer at the door until close, then push through it
		_press_toward(to_door.normalized() if to_door.length() > 30.0 else outward)
		await get_tree().physics_frame
	_release_moves()
	if room_number == 1:
		_check("walking into an open door starts the next room", _gm.room_index == 2)
	else:
		_check_quiet("walking through a door in room %d" % room_number, _gm.room_index == room_number + 1)
	# on the floor, off the tome walls, and no object under their feet
	var at := _player.global_position
	var clear := Geometry2D.is_point_in_polygon(at, _room._floor_polygon) 			and not _room._inside_fixture(at, 8.0)
	for o in _room.objects.get_children():
		if (o as Node2D).global_position.distance_to(at) < RoomManager.ENTRY_CLEARANCE_PX - 0.01:
			clear = false
	_check_quiet("the player arrives on clear floor", clear)


# --------------------------------------------------------------------------
# Environmental Combat. Runs in a cleared room, so nothing else interferes.
# --------------------------------------------------------------------------

func _spawn_object(kind: int, at: Vector2) -> EnvObject:
	var obj := _room.OBJECT_SCENES[kind].instantiate() as EnvObject
	obj.global_position = at
	_room.objects.add_child(obj)
	return obj


## A test dummy: a real Enemy that stands still and is not counted by the room.
func _spawn_dummy(species: String, at: Vector2) -> Enemy:
	var e := _room.ENEMY_SCENE.instantiate() as Enemy
	e.species = species
	e.global_position = at
	_room.enemies.add_child(e)
	e.set_physics_process(false)
	return e


func _clear_stage() -> void:
	for o in _room.objects.get_children():
		_room.objects.remove_child(o)
		o.queue_free()
	for e in _room.enemies.get_children():
		_room.enemies.remove_child(e)
		e.queue_free()


func _environment_checks() -> void:
	_clear_stage()
	# Always the same open floor, whatever layout room 2 drew, so every
	# distance below means the same thing on every run.
	for i in RoomLayouts.count():
		var e := RoomLayouts.entry(i)
		if (e.get("fixtures", []) as Array).is_empty() and not e.get("boss", false) 				and not e.get("standin", false):
			_room.load_layout(i, false)
			break
	var c := _room._nearest_open_point(_room.floor_centre())
	var far := Vector2(0, 150)          # where the knight waits, out of every radius
	_player.global_position = c + far
	_player.is_invulnerable = false
	await _frames(3)

	# ---- barrel ----
	var barrel := _spawn_object(0, c)
	var near := _spawn_dummy("snail", c + Vector2(90, 0))
	var outside := _spawn_dummy("snail", c + Vector2(-100, 0))
	var weak := _spawn_dummy("snail", c + Vector2(0, -60))
	weak.hp = 20
	var elite := _spawn_dummy("grotesque", c + Vector2(60, -40))
	elite.hp = 30
	var cover := _spawn_object(1, c + Vector2(-60, 40))
	await _frames(2)
	barrel.take_hit("player")
	_check("barrel survives the first hit", not barrel.is_spent() and near.hp == 40)
	_energy.clear()
	var hp_before := _player.hp
	barrel.take_hit("player")
	_check("barrel detonates on the second hit", barrel.is_spent())
	_check("blast deals 30 to an enemy within 96 px", near.hp == 10, "hp %d" % near.hp)
	_check("blast does not reach an enemy at 100 px", outside.hp == 40, "hp %d" % outside.hp)
	_check("a barrel kill pays double energy: standard 10, elite 30",
			_energy.has([10, true]) and _energy.has([30, true]), str(_energy))
	_check("the blast is one hit on cover in range", cover.hits_taken == 1, "hits %d" % cover.hits_taken)
	_check("a blast 150 px away does not touch the player", _player.hp == hp_before)
	await _seconds(0.5)

	# ---- barrel chain, and the player in the blast ----
	_clear_stage()
	var b1 := _spawn_object(0, c)
	var b2 := _spawn_object(0, c + Vector2(80, 0))
	var chained := _spawn_dummy("snail", c + Vector2(160, 0))   # only b2 reaches it
	_player.global_position = c + Vector2(0, 50)
	await _frames(2)
	hp_before = _player.hp
	b1.take_hit("player")
	b1.take_hit("player")
	await _frames(3)
	_check("a blast sets off other barrels in range", b2.is_spent() and chained.hp == 10, "hp %d" % chained.hp)
	_check("standing in a blast costs the player 30", _player.hp == hp_before - 30, "hp %d" % _player.hp)
	await _seconds(0.5)

	# ---- Shockwave x barrel (Daryl -> K'von) ----
	_clear_stage()
	_player.global_position = c + far
	var b3 := _spawn_object(0, _player.global_position + Vector2(120, 0))
	var meter := _player.get_node("GrazeMeter")
	meter.add_meter(100)
	await _frames(2)
	(_player.get_node("Shockwave") as Shockwave).try_fire()
	_check("Shockwave detonates a barrel inside 150 px at once", b3.is_spent())
	await _seconds(1.2)
	_player.is_invulnerable = false

	# ---- cover ----
	_clear_stage()
	_player.global_position = c + far
	var wall := _spawn_object(1, c + Vector2(0, 100))    # between the bullet and the knight
	await _frames(2)
	hp_before = _player.hp
	var bullet := load("res://scenes/EnemyBullet.tscn").instantiate() as EnemyBullet
	bullet.direction = Vector2.DOWN
	bullet.global_position = c + Vector2(0, 40)
	add_child(bullet)
	await _seconds(0.6)
	_check("cover blocks an enemy bullet", _player.hp == hp_before and wall.hits_taken == 1 and not is_instance_valid(bullet),
			"hp %d, cover hits %d" % [_player.hp, wall.hits_taken])
	for i in 3:
		wall.take_hit("player")
	_check("cover still stands after 4 hits", not wall.is_spent())
	wall.take_hit("enemy")
	_check("cover breaks on the 5th hit, from any source", wall.is_spent())
	await _frames(3)
	bullet = load("res://scenes/EnemyBullet.tscn").instantiate() as EnemyBullet
	bullet.direction = Vector2.DOWN
	bullet.global_position = c + Vector2(0, 40)
	add_child(bullet)
	await _seconds(0.6)
	_check("broken cover no longer blocks", _player.hp == hp_before - 10, "hp %d" % _player.hp)
	await _seconds(0.5)

	# ---- trap ----
	_clear_stage()
	_player.global_position = c + far
	var trap := _spawn_object(2, c)
	await _frames(3)
	_check("a trap starts armed", trap.trap_armed)
	var walker := _spawn_dummy("grotesque", c)       # 120 HP: survives two bites
	await _frames(4)
	_check("trap deals 15 to the enemy that steps on it", walker.hp == 105, "hp %d" % walker.hp)
	_check("a fired trap is disarmed", not trap.trap_armed)
	await _seconds(1.8)
	_check("still disarmed after 1.8 s", not trap.trap_armed and walker.hp == 105)
	await _seconds(0.4)
	_check("re-arms after 2 s and bites whoever is still on it", walker.hp == 90, "hp %d" % walker.hp)
	_room.enemies.remove_child(walker)
	walker.queue_free()
	await _seconds(2.2)
	_check("armed again once the plate is empty", trap.trap_armed)
	var victim := _spawn_dummy("snail", c)
	victim.hp = 10
	_energy.clear()
	await _frames(4)
	_check("a trap kill pays double energy", _energy == [[10, true]], str(_energy))
	await _seconds(2.2)
	hp_before = _player.hp
	_player.global_position = c
	await _frames(4)
	_check("trap deals 15 to the player who steps on it", _player.hp == hp_before - 15, "hp %d" % _player.hp)

	# ---- knockback onto a trap (Daryl -> K'von) ----
	_clear_stage()
	_player.global_position = c + far
	_player.hp = 100
	await _seconds(0.5)
	var plate := _spawn_object(2, _player.global_position + Vector2(0, -105))
	var pushed := _room.ENEMY_SCENE.instantiate() as Enemy
	pushed.species = "snail"
	pushed.global_position = _player.global_position + Vector2(0, -45)
	_room.enemies.add_child(pushed)
	meter.add_meter(100)
	await _frames(2)
	var fires := [0]
	plate.trap_triggered.connect(func(_v: Node2D) -> void: fires[0] += 1)
	(_player.get_node("Shockwave") as Shockwave).try_fire()
	await _seconds(0.6)
	# 40 HP - 30 Shockwave = 10, and the trap's 15 finishes it
	_check("Shockwave knockback can push an enemy onto a trap", fires[0] >= 1, "trap fired %d times" % fires[0])
	await _seconds(0.6)

	_clear_stage()
	_player.is_invulnerable = true
	_player.hp = 60
	_room.bake_navigation()


func _finish() -> void:
	_release_moves()
	print("\n%d passed, %d failed" % [_passed, _failed])
	Engine.time_scale = 1.0
	get_tree().quit(0 if _failed == 0 else 1)
