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
	match _frame:
		20:
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
			# jump to the boss room for a look at the arena and the scribe
			Input.action_release("shoot")
			var gm := GameManager.instance
			gm.room_index = GameManager.BOSS_ROOM - 1
			gm._advance_room("DoorNorth")
		290:
			_shot("05_boss_arena")
		340:
			Input.action_press("shoot")
			Input.warp_mouse(vp.get_visible_rect().size * Vector2(0.5, 0.2))
		420:
			_shot("06_boss_fight")
			_report()
		430:
			# leave the boss one hit from death; the knight is still firing
			for e in get_tree().get_nodes_in_group("enemy"):
				e.set("hp", 1)
			Input.warp_mouse(vp.get_visible_rect().size * Vector2(0.5, 0.33))
		520:
			_shot("07_win")
			var gm := GameManager.instance
			print("[report] run_over=%s hud_end_visible=%s" % [
				str(gm.is_run_over), str(gm.hud.end_screen.visible)])
		530:
			get_tree().quit()


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
