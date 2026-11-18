extends Node
## Focused headless regression tests for Bullet Grazing and Shockwave.
##
## Run with:
##   godot --headless --path . res://tests/MechanicsTest.tscn

const PLAYER_SCENE: PackedScene = preload("res://scenes/Player.tscn")
const ENEMY_SCENE: PackedScene = preload("res://scenes/Enemy.tscn")
const ENEMY_BULLET_SCENE: PackedScene = preload("res://scenes/EnemyBullet.tscn")
const BARREL_SCENE: PackedScene = preload("res://scenes/Barrel.tscn")
const TRAP_SCENE: PackedScene = preload("res://scenes/Trap.tscn")
const HUD_SCENE: PackedScene = preload("res://scenes/HUD.tscn")
const MAIN_SCENE: PackedScene = preload("res://scenes/Main.tscn")

var _failures: Array[String] = []
var _passes: int = 0
var _integration_entries: int = 0
var _integration_exits: int = 0


func _ready() -> void:
	await get_tree().process_frame
	await _test_real_scene_grazing()
	await _test_bullet_grazing()
	await _test_shockwave()
	await _test_hud_pulse()
	await _test_room_encounter_graze_hud()

	if _failures.is_empty():
		print("[mechanics-test] PASS: %d checks" % _passes)
		get_tree().quit(0)
	else:
		for failure in _failures:
			push_error("[mechanics-test] " + failure)
		print("[mechanics-test] FAIL: %d passed, %d failed" % [
				_passes, _failures.size()])
		get_tree().quit(1)


func _test_real_scene_grazing() -> void:
	var world := Node2D.new()
	world.name = "RealGrazeWorld"
	add_child(world)
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2(400, 300)
	world.add_child(player)
	await get_tree().process_frame
	var meter := player.get_node("GrazeMeter") as GrazeMeter
	var graze_area := player.get_node("GrazeArea") as Area2D
	_integration_entries = 0
	_integration_exits = 0
	graze_area.area_entered.connect(_record_integration_entry)
	graze_area.area_exited.connect(_record_integration_exit)

	# The combined hit radii are 13 px and the graze threshold is another
	# 20 px. A 25 px offset therefore misses the hitbox but crosses the graze
	# band. The real EnemyBullet script supplies all movement.
	var near_miss := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	near_miss.position = Vector2(300, 325)
	near_miss.direction = Vector2.RIGHT
	world.add_child(near_miss)
	for _frame in range(120):
		if near_miss.position.x > 530.0:
			break
		await get_tree().physics_frame
	print("[mechanics-test] graze trace: entered=%d exited=%d pending=%d meter=%d" % [
			_integration_entries, _integration_exits,
			meter.pending_graze_ids.size(), meter.meter])
	_check(_integration_entries == 1 and _integration_exits == 1,
			"Real near-miss bullet enters and exits GrazeArea once")
	_check(meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE,
			"Real near-miss awards +5 before any enemy is defeated")

	# A direct hit follows the same real movement path through the GrazeArea.
	# Starting from 50 makes the required -25 result distinguishable from both
	# a reset-to-zero bug and the old +5-then-hit behavior.
	meter.meter = 50
	player._hit_timer = 0.0
	var direct_hit := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	direct_hit.position = Vector2(300, 300)
	direct_hit.direction = Vector2.RIGHT
	world.add_child(direct_hit)
	for _frame in range(120):
		if player.hp < Player.MAX_HP:
			break
		await get_tree().physics_frame
	await get_tree().physics_frame
	_check(player.hp == Player.MAX_HP - EnemyBullet.DAMAGE,
			"Real direct-hit bullet damages the player")
	_check(meter.meter == 25,
			"Real direct hit gives no graze and subtracts exactly 25")

	_check(CombatRewards.energy_for("standard") == 5
			and CombatRewards.energy_for("elite") == 15
			and CombatRewards.energy_for("boss") == 30,
			"Combat Rewards energy remains 5 / 15 / 30")

	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _record_integration_entry(area: Area2D) -> void:
	if area is EnemyBullet:
		_integration_entries += 1


func _record_integration_exit(area: Area2D) -> void:
	if area is EnemyBullet:
		_integration_exits += 1


func _test_bullet_grazing() -> void:
	var world := Node2D.new()
	world.name = "GrazingWorld"
	add_child(world)
	var player := PLAYER_SCENE.instantiate() as Player
	world.add_child(player)
	await get_tree().process_frame
	var meter := player.graze_meter as GrazeMeter

	var safe_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	safe_bullet.position = Vector2(400, 0)
	world.add_child(safe_bullet)
	await get_tree().process_frame

	meter._on_graze_area_entered(safe_bullet)
	_check(meter.meter == 0,
			"Graze credit waits until the bullet safely exits")
	meter._on_graze_area_exited(safe_bullet)
	_check(meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE,
			"Safe graze awards exactly +5")

	meter._on_graze_area_entered(safe_bullet)
	meter._on_graze_area_exited(safe_bullet)
	_check(meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE,
			"The same bullet cannot award a second graze")

	var destroyed_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	destroyed_bullet.position = Vector2(400, 0)
	world.add_child(destroyed_bullet)
	await get_tree().process_frame
	meter._on_graze_area_entered(destroyed_bullet)
	destroyed_bullet.queue_free()
	meter._on_graze_area_exited(destroyed_bullet)
	_check(meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE,
			"A bullet destroyed inside the graze band gives no credit")

	# Regression: the old implementation awarded +5 on entry and then applied
	# -25 on hit, leaving 30 from a starting value of 50. Correct is 25.
	meter.meter = 50
	var hit_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	hit_bullet.position = Vector2(400, 0)
	world.add_child(hit_bullet)
	await get_tree().process_frame
	meter._on_graze_area_entered(hit_bullet)
	hit_bullet._on_body_entered(player)
	meter._on_graze_area_exited(hit_bullet)
	_check(meter.meter == 25,
			"A bullet that hits gives no graze credit and applies -25")

	player._hit_timer = 0.0
	meter.meter = 10
	player.take_damage(EnemyBullet.DAMAGE)
	_check(meter.meter == 0,
			"Damage penalty is clamped at zero")

	world.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame


func _test_shockwave() -> void:
	var world := Node2D.new()
	world.name = "ShockwaveWorld"
	add_child(world)
	var player := PLAYER_SCENE.instantiate() as Player
	player.position = Vector2.ZERO
	world.add_child(player)
	await get_tree().process_frame
	var meter := player.graze_meter as GrazeMeter
	var shockwave := player.shockwave as Shockwave

	meter.add_meter(99)
	_check(not shockwave.is_ready and not shockwave.try_fire(),
			"Shockwave cannot activate below 100 meter")
	meter.add_meter(1)
	_check(shockwave.is_ready, "Shockwave becomes ready at exactly 100 meter")

	var near_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	near_bullet.position = Vector2(0, 100)
	world.add_child(near_bullet)
	var far_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	far_bullet.position = Vector2(0, 200)
	world.add_child(far_bullet)

	var near_enemy := ENEMY_SCENE.instantiate() as Enemy
	near_enemy.position = Vector2(100, 0)
	world.add_child(near_enemy)
	var far_enemy := ENEMY_SCENE.instantiate() as Enemy
	far_enemy.position = Vector2(250, 0)
	world.add_child(far_enemy)

	var barrel := BARREL_SCENE.instantiate() as EnvObject
	barrel.position = Vector2(-100, 0)
	world.add_child(barrel)
	await get_tree().process_frame

	_check(shockwave.try_fire(), "Ready Shockwave activates")
	_check(meter.meter == 0, "Shockwave consumes the entire meter")
	_check(player.is_invulnerable, "Player is invulnerable during activation")
	var hp_before := player.hp
	player.take_damage(EnemyBullet.DAMAGE)
	_check(player.hp == hp_before, "Activation invulnerability blocks damage")
	_check(near_bullet.is_queued_for_deletion(),
			"Enemy bullet inside 150 px is destroyed")
	_check(not far_bullet.is_queued_for_deletion(),
			"Enemy bullet outside 150 px survives")
	_check(near_enemy.hp == near_enemy.max_hp - Shockwave.ENEMY_DAMAGE,
			"Enemy inside 150 px takes 30 damage")
	_check(far_enemy.hp == far_enemy.max_hp,
			"Enemy outside 150 px takes no damage")
	_check(barrel._detonated, "Barrel inside 150 px detonates")
	_check(not shockwave.try_fire(), "Shockwave cannot fire again while spent")

	await _wait_for_knockback(near_enemy)
	_check(is_equal_approx(near_enemy.position.x, 150.0)
			and is_equal_approx(near_enemy.position.y, 0.0),
			"Unobstructed Shockwave knockback travels exactly 50 px")

	# Collision-safety regression: a wall must stop the requested displacement.
	var wall := StaticBody2D.new()
	wall.collision_layer = 32
	wall.position = Vector2(40, 300)
	var wall_shape := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(10, 100)
	wall_shape.shape = rectangle
	wall.add_child(wall_shape)
	world.add_child(wall)
	var blocked_enemy := ENEMY_SCENE.instantiate() as Enemy
	blocked_enemy.position = Vector2(0, 300)
	world.add_child(blocked_enemy)
	await get_tree().process_frame
	blocked_enemy.apply_knockback(Vector2(50, 0))
	await _wait_for_knockback(blocked_enemy)
	_check(blocked_enemy.position.x < 25.0,
			"Knockback stops safely at blocking collision")

	# Traps are nonblocking Area2D triggers, so collision-safe movement must
	# still cross them and preserve the Shockwave/environment cross-link.
	var trap := TRAP_SCENE.instantiate() as EnvObject
	trap.position = Vector2(80, 500)
	world.add_child(trap)
	var trapped_enemy := ENEMY_SCENE.instantiate() as Enemy
	trapped_enemy.position = Vector2(0, 500)
	world.add_child(trapped_enemy)
	await get_tree().process_frame
	trapped_enemy.apply_knockback(Vector2(50, 0))
	await _wait_for_knockback(trapped_enemy)
	await get_tree().physics_frame
	_check(trapped_enemy.hp == trapped_enemy.max_hp - EnvObject.TRAP_DAMAGE,
			"Knockback can still push an enemy onto a trap")

	await get_tree().create_timer(Shockwave.ACTIVATION_SECONDS + 0.05).timeout
	_check(not player.is_invulnerable,
			"Shockwave invulnerability ends after one second")
	player._hit_timer = 0.0
	player.take_damage(EnemyBullet.DAMAGE)
	_check(player.hp == hp_before - EnemyBullet.DAMAGE,
			"Player takes damage after invulnerability ends")

	world.queue_free()
	await get_tree().process_frame


func _wait_for_knockback(enemy: Enemy) -> void:
	for _frame in range(60):
		if not enemy.is_knockback_active():
			return
		await get_tree().physics_frame
	_failures.append("Knockback did not finish within 60 physics frames")


func _test_hud_pulse() -> void:
	var hud := HUD_SCENE.instantiate()
	add_child(hud)
	await get_tree().process_frame
	hud.call("_on_meter_full")
	var first_pulse := hud.get("_shockwave_pulse") as Tween
	_check(first_pulse != null and first_pulse.is_valid(),
			"HUD starts one Shockwave-ready pulse tween")
	hud.call("_on_meter_not_full")
	_check((first_pulse == null or not first_pulse.is_valid())
			and hud.get("_shockwave_pulse") == null,
			"HUD stops and releases the ready pulse when meter is spent")
	hud.call("_on_meter_full")
	var second_pulse := hud.get("_shockwave_pulse") as Tween
	_check(second_pulse != null and second_pulse != first_pulse
			and second_pulse.is_valid(),
			"HUD creates only a fresh pulse for the next ready state")
	hud.call("_on_meter_not_full")
	hud.queue_free()
	await get_tree().process_frame


func _test_room_encounter_graze_hud() -> void:
	var main := MAIN_SCENE.instantiate() as GameManager
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	var meter := main.player.get_node("GrazeMeter") as GrazeMeter
	var meter_bar := main.hud.get_node("Root/BottomCentre/MeterBar") as ProgressBar
	var meter_label := main.hud.get_node(
			"Root/BottomCentre/MeterBar/MeterLabel") as Label
	var kills_before := CombatRewards.kill_count

	var room_bullet := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	room_bullet.global_position = main.player.global_position + Vector2(-100, 25)
	room_bullet.direction = Vector2.RIGHT
	add_child(room_bullet)
	var exit_x := main.player.global_position.x + 130.0
	for _frame in range(120):
		if room_bullet.global_position.x > exit_x:
			break
		await get_tree().physics_frame
	await get_tree().create_timer(0.2).timeout

	_check(meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE
			and CombatRewards.kill_count == kills_before,
			"Room encounter graze adds +5 without an enemy kill")
	_check(is_equal_approx(meter_bar.value, 5.0)
			and meter_label.text == "GRAZE  5 / 100",
			"Room encounter graze propagates to the HUD")

	main.queue_free()
	GameManager.instance = null
	await get_tree().process_frame


func _check(condition: bool, description: String) -> void:
	if condition:
		_passes += 1
		print("[mechanics-test] PASS: " + description)
	else:
		_failures.append(description)
