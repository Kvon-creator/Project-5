extends Node
## Visual check harness. Not part of the game.
##
## Instances Main, drives the knight with fake input for a few seconds while
## the first wave comes in, and saves PNGs to build/shots/. Run it windowed:
##
##   godot --path . res://tests/Screenshot.tscn
##
## It quits on its own. The PNGs are the thing to look at next to the
## reference images.

const OUT_DIR := "res://build/shots/"

var _frame: int = 0
var _main: Node


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_main = load("res://scenes/Main.tscn").instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frame += 1
	var vp := get_viewport()
	if _frame > 690 and _frame < 790:
		_aim_at_nearest_enemy()
	match _frame:
		8:
			_layout_sweep()   # async, ~6 frames; restores room 1 before the first wave
		30:
			_shot("01_room")
		70:
			# the first wave has spawned; walk right and open fire to the right
			Input.action_press("move_right")
			Input.action_press("shoot")
			Input.warp_mouse(vp.get_visible_rect().size * Vector2(0.9, 0.5))
		100:
			_shot("02_wave_in")
		130:
			Input.action_release("move_right")
			Input.action_press("move_down")
			Input.action_press("move_left")
			Input.warp_mouse(vp.get_visible_rect().size * Vector2(0.2, 0.3))
		170:
			_shot("03_combat")
		200:
			Input.action_release("move_down")
			Input.action_release("move_left")
		260:
			_shot("04_later")
			_report()
		270:
			# hazard-avoidance check: a trap straight between a grotesque and the
			# standing-still knight. GDD: enemies steer clear within 75 px.
			Input.action_release("shoot")
			_hazard_setup()
		490:
			_hazard_report()
			# jump to the boss room for a look at the arena and the scribe
			var gm := GameManager.instance
			gm.room_index = GameManager.BOSS_ROOM - 1
			gm._advance_room("DoorNorth")
		510:
			_shot("05_boss_arena")
		560:
			Input.action_press("shoot")
			Input.warp_mouse(vp.get_visible_rect().size * Vector2(0.5, 0.2))
		640:
			_shot("06_boss_fight")
			_report()
		600:
			# phase check: drop the boss to 50% then 20% and watch the phases turn
			for e in get_tree().get_nodes_in_group("enemy"):
				if e.get("species") == "scribe":
					e.set("hp", int(e.max_hp * 0.5)); e.take_damage(1)
		620:
			_boss_report("after 50%")
		660:
			for e in get_tree().get_nodes_in_group("enemy"):
				if e.get("species") == "scribe":
					e.set("hp", int(e.max_hp * 0.2)); e.take_damage(1)
		680:
			_boss_report("after 20%")
		690:
			# leave the boss one hit from death, and stand where the knight
			# has a clear shot - the scribe takes cover now, which is right,
			# but this is a test of the win screen, not of the cover.
			for e in get_tree().get_nodes_in_group("enemy"):
				e.set("hp", 1)
				if e.get("species") == "scribe":
					GameManager.instance.player.global_position = (e as Node2D).global_position + Vector2(0, 110)
		790:
			_shot("07_win")
			var gm := GameManager.instance
			print("[report] run_over=%s hud_end_visible=%s" % [
				str(gm.is_run_over), str(gm.hud.end_screen.visible)])
		800:
			get_tree().quit()


var _trap_hits: int = 0
var _hazard_runner: Enemy
var _hazard_trap: Node2D


func _hazard_setup() -> void:
	var gm := GameManager.instance
	for e in get_tree().get_nodes_in_group("enemy"):
		e.queue_free()
	for b in get_tree().get_nodes_in_group("enemy_bullet"):
		b.queue_free()
	gm.room.enemies_alive = 0
	gm.player.global_position = gm.room.floor_centre() + Vector2(0, 120)
	var p: Vector2 = gm.player.global_position
	_hazard_trap = gm.room.OBJECT_SCENES[2].instantiate()      # Trap.tscn
	_hazard_trap.global_position = p + Vector2(0, -110)
	gm.room.objects.add_child(_hazard_trap)
	_hazard_trap.trap_triggered.connect(func(_v: Node2D) -> void: _trap_hits += 1)
	gm.room.bake_navigation.call_deferred()
	gm.room._spawn_enemy("grotesque", p + Vector2(0, -230))
	_hazard_runner = gm.room.enemies.get_child(gm.room.enemies.get_child_count() - 1) as Enemy
	_hazard_runner._path_timer = 0.0   # recalc now, not in two seconds
	print("[hazard] setup: knight=%s trap=%s runner=%s" % [str(p), str(_hazard_trap.global_position), str(_hazard_runner.global_position)])


func _hazard_report() -> void:
	var gm := GameManager.instance
	var p: Vector2 = gm.player.global_position
	var s: Vector2 = _hazard_runner.global_position if is_instance_valid(_hazard_runner) else Vector2.INF
	var closest := _hazard_trap.global_position.distance_to(s)
	var verdict := "STEPPED ON IT"
	if _trap_hits == 0:
		verdict = "AVOIDED AND GOT PAST" if p.distance_to(s) < 90.0 else "AVOIDED BUT STUCK"
	print("[hazard] after 220 frames: runner=%s dist_to_knight=%.0f dist_to_trap=%.0f trap_triggered=%d -> %s" % [
		str(s), p.distance_to(s), closest, _trap_hits, verdict])


## Point the mouse at the nearest living enemy's feet (screen space).
func _aim_at_nearest_enemy() -> void:
	var gm := GameManager.instance
	var best: Node2D = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemy"):
		var d: float = (e as Node2D).global_position.distance_to(gm.player.global_position)
		if e.get("species") == "scribe":
			d = 0.0   # the boss is the target whenever it is alive
		if d < best_d:
			best_d = d
			best = e
	if best:
		Input.warp_mouse(best.get_global_transform_with_canvas().origin)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + name + ".png"
	img.save_png(path)
	print("[shot] ", path, "  ", img.get_width(), "x", img.get_height())


func _report() -> void:
	var gm := GameManager.instance
	if gm == null:
		print("[report] no GameManager")
		return
	var enemies := get_tree().get_nodes_in_group("enemy")
	var species: Array[String] = []
	for e in enemies:
		species.append(str(e.get("species")))
	print("[report] room=%d hp=%d enemies_alive=%d species=%s bullets=%d objects=%d player=%s" % [
		gm.room_index, gm.player.hp, gm.room.enemies_alive, str(species),
		get_tree().get_nodes_in_group("enemy_bullet").size(),
		get_tree().get_nodes_in_group("env_object").size(),
		str(gm.player.global_position)])
	var navpoly: NavigationPolygon = gm.room.nav_region.navigation_polygon
	var paths: Array[int] = []
	for e in enemies:
		paths.append((e as Enemy).agent.get_current_navigation_path().size())
	print("[nav] mesh_polygons=%d outlines=%d path_points_per_enemy=%s" % [
		navpoly.get_polygon_count() if navpoly else -1,
		navpoly.get_outline_count() if navpoly else -1, str(paths)])


## Load every layout once: it must apply, place its fixtures and bake.
func _layout_sweep() -> void:
	var gm := GameManager.instance
	var lines: Array[String] = []
	for i in RoomLayouts.count():
		gm.room.load_layout(i, false)
		gm.room.bake_navigation()
		var navpoly: NavigationPolygon = gm.room.nav_region.navigation_polygon
		lines.append("%s(%s fx=%d poly=%d)" % [RoomLayouts.entry(i).get("name", "?"), gm.room.layout_title,
				gm.room.fixtures.get_child_count(), navpoly.get_polygon_count() if navpoly else -1])
	print("[layouts] ", " ".join(lines))
	# two of the new layouts, each given a frame to draw before capture
	for pick in [["room_05", "04b_mirrored_hall"], ["room_09", "04c_elite_court"]]:
		for i in RoomLayouts.count():
			if RoomLayouts.entry(i).get("name", "") == pick[0]:
				gm.room.load_layout(i, false)
				gm.room.bake_navigation()
		await get_tree().process_frame
		await _shot(pick[1])
	# back to the layout the run started in
	gm.room.load_layout(gm.room.used_layouts[0] if gm.room.used_layouts.size() > 0 else 0, false)
	gm.room.bake_navigation()


func _boss_report(when: String) -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if e.get("species") == "scribe":
			print("[boss] %s: phase=%d hp=%d/%d minions=%d bullets=%d boss_bar_visible=%s label='%s'" % [
				when, e.boss_phase, e.hp, e.max_hp, get_tree().get_nodes_in_group("enemy").size() - 1,
				get_tree().get_nodes_in_group("enemy_bullet").size(),
				str(GameManager.instance.hud.boss_box.visible), GameManager.instance.hud.boss_label.text])
