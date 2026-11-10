class_name GameManager
extends Node2D
## Run state: Win and lose.
##
## OWNER: K'von Gates, by Nov 18.
## GDD architecture box: "GameManager.gd / Main.tscn, autoload / Win and lose:
## run state, room index 1-8".
## Reads: RoomManager, Player
##        ("Room cleared -> next room; HP 0 -> lose").
##
## A note on "Main.tscn, autoload". In Godot a script cannot be both a scene
## root's script and an autoload singleton - those are two different things.
## The GDD box asks for both, so this resolves it the normal Godot way: the
## script lives on Main.tscn's root (which IS the main scene, so it is always
## present), and exposes a `static var instance` so any script can reach it
## like an autoload, via `GameManager.instance`. Only CombatRewards and
## Palette are true autoloads.
##
## WHAT IS BUILT: scene wiring, the room counter, the victory and defeat
## screens, run reset.
## WHAT IS NOT: advancing between rooms, which waits on RoomManager.

## "Rooms per run 8"
const ROOMS_PER_RUN: int = 8
const BOSS_ROOM: int = 8

signal run_started
signal room_changed(room_index: int)
signal run_won
signal run_lost

static var instance: GameManager

var room_index: int = 1
var is_run_over: bool = false

@onready var player: Player = $Player
@onready var room: RoomManager = $Room
@onready var hud: CanvasLayer = $HUD
@onready var camera: Camera2D = $Player/Camera


func _ready() -> void:
	instance = self
	Palette.check_no_magenta(self)

	# Built wiring. These are the two links the GDD names for this script, and
	# getting them connected is the scaffold's job even though the handlers
	# are stubs.
	if player:
		player.died.connect(_on_player_died)
	if room:
		room.room_cleared.connect(_on_room_cleared)

	start_run()


func start_run() -> void:
	is_run_over = false
	room_index = 1
	# GDD, Win and lose: "HP, Graze Meter and damage boost reset; nothing
	# carries over between runs."
	CombatRewards.reset_for_new_run()
	run_started.emit()
	room_changed.emit(room_index)
	room.start_room(room_index)


func _on_room_cleared(_cleared_index: int) -> void:
	if is_run_over:
		return

	# GDD: "Room-clear heal +10 HP, capped at 100 (proposed)".
	player.heal_room_clear()

	if room_index >= BOSS_ROOM:
		win()
		return

	# TODO(K'von): advance to the next room. The doors are already unlocked
	# by RoomManager; this should wait for the player to actually walk
	# through one ("WASD to walk through a door. Crossing the threshold
	# starts the room.") rather than teleporting them.
	#   room_index += 1
	#   room_changed.emit(room_index)
	#   room.start_room(room_index)


func _on_player_died() -> void:
	lose()


## GDD: "Win: defeat the boss in room 8 (1,200 HP (proposed)). The run ends
## with a victory screen."
func win() -> void:
	if is_run_over:
		return
	is_run_over = true
	run_won.emit()
	hud.show_end_screen(true)


## GDD: "Lose: player HP reaches 0 in any room. The run ends and the player
## restarts at room 1 with a new random set of layouts and objects."
func lose() -> void:
	if is_run_over:
		return
	is_run_over = true
	player.play_death()
	run_lost.emit()
	hud.show_end_screen(false)


## Called by the end screen's button.
func restart() -> void:
	get_tree().reload_current_scene()
