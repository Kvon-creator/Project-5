extends Node
## Checks the dodge (Dodge.gd), its i-frames, how it works with grazing, and
## the knight's hitbox. Not part of the game.
##
##   godot --headless --path . res://tests/DodgeTest.tscn

const ENEMY_BULLET_SCENE: PackedScene = preload("res://scenes/EnemyBullet.tscn")

var _gm: GameManager
var _room: RoomManager
var _player: Player
var _meter: GrazeMeter
var _passed := 0
var _failed := 0
var _c: Vector2


func _ready() -> void:
	add_child(load("res://scenes/Main.tscn").instantiate())
	_gm = GameManager.instance
	_room = _gm.room
	_player = _gm.player
	_meter = _player.get_node("GrazeMeter") as GrazeMeter
	_gm.loot.enabled = false
	_run.call_deferred()


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
	await _frames(int(ceil(s * Engine.physics_ticks_per_second / Engine.time_scale)))


func _hitbox() -> Rect2:
	return (_player.get_node("SpriteHitbox") as SpriteHitbox).global_rect()


func _reset() -> void:
	_room.stop()
	for group in ["enemy", "enemy_bullet", "player_bullet", "env_object", "item_pickup"]:
		for n in get_tree().get_nodes_in_group(group):
			n.get_parent().remove_child(n)
			n.queue_free()
	_room.enemies_alive = 0
	_player.set_physics_process(true)
	_player.hp = Player.MAX_HP
	_player.set("_hit_timer", 0.0)
	_player.global_position = _c
	_meter.meter = 0
	_meter.reset_for_new_room()
	await _seconds(Dodge.COOLDOWN + 0.4)   # any earlier dodge has worn off


func _bullet(at: Vector2, dir: Vector2) -> EnemyBullet:
	var b := ENEMY_BULLET_SCENE.instantiate() as EnemyBullet
	b.direction = dir
	b.global_position = at
	get_tree().current_scene.add_child(b)
	return b


func _run() -> void:
	for i in RoomLayouts.count():
		var e := RoomLayouts.entry(i)
		if (e.get("fixtures", []) as Array).is_empty() and not e.get("boss", false) \
				and not e.get("standin", false):
			_room.load_layout(i, false)
			break
	_c = _room._nearest_open_point(_room.floor_centre())

	await _hitbox_checks()
	await _dodge_basics()
	await _dodge_and_graze()
	await _shadow_step()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# --------------------------------------------------------------------------

func _hitbox_checks() -> void:
	await _reset()
	# Face right, still, so the staff is on the right.
	_player.set_physics_process(false)
	_player.aim_direction = Vector2.RIGHT
	_player.sprite.flip_h = false
	await _frames(2)
	var r := _hitbox()
	var feet := _player.global_position
	_check("the knight's hitbox is his body: 68 px wide, not the 122 px sprite",
			absf(r.size.x - 68.0) < 1.0 and absf(r.size.y - 84.0) < 1.5, str(r.size))
	_check("and it sits over his sprite, from plume to boots",
			r.position.y < feet.y - 70.0 and r.end.y > feet.y)
	# A shot falling through the staff's head, right of his hand.
	# (both start inside the room, below the back wall)
	var through_staff := _bullet(Vector2(feet.x + 35.0, feet.y - 130.0), Vector2.DOWN)
	var staff_crossed := [false]
	await _seconds(1.2)
	staff_crossed[0] = not is_instance_valid(through_staff) or through_staff.global_position.y > feet.y + 20.0
	_check("a shot through the staff does not hit him", _player.hp == 100 and staff_crossed[0],
			"hp %d" % _player.hp)
	if is_instance_valid(through_staff):
		through_staff.queue_free()
	var body_shot := _bullet(Vector2(feet.x - 20.0, feet.y - 130.0), Vector2.DOWN)
	await _seconds(1.2)
	_check("a shot through his body does", _player.hp == 90, "hp %d" % _player.hp)
	if is_instance_valid(body_shot):
		body_shot.queue_free()
	# flipped: the box mirrors with him
	_player.sprite.flip_h = true
	await _frames(2)
	var rf := _hitbox()
	_check("facing left, the box mirrors to stay on his body",
			absf((rf.get_center().x - feet.x) + (r.get_center().x - feet.x)) < 1.0,
			"%.1f vs %.1f" % [r.get_center().x - feet.x, rf.get_center().x - feet.x])
	_player.set_physics_process(true)


func _dodge_basics() -> void:
	await _reset()
	_check("the dodge is there with no items", _player.dodge != null and _player.dodge.is_ready())
	_player.aim_direction = Vector2.LEFT
	var start := _player.global_position
	_check("SPACE dodges", _player.dodge.try_dodge())
	_check("mid-dodge he is invulnerable", _player.is_phasing())
	_player.take_damage(10)
	_check("a hit mid-dodge does nothing", _player.hp == 100)
	await _seconds(Dodge.SECONDS + 0.05)
	var moved := _player.global_position.distance_to(start)
	_check("the dodge covers about 110 px", absf(moved - Dodge.DISTANCE_PX) < 15.0, "%.0f px" % moved)
	_check("it cannot be chained", not _player.dodge.try_dodge())
	await _seconds(Dodge.IFRAMES)
	_check("the i-frames end", not _player.is_phasing())
	_player.take_damage(10)
	_check("and he can be hurt again", _player.hp == 90)
	await _seconds(Dodge.COOLDOWN)
	_check("ready again after %.1f s" % Dodge.COOLDOWN, _player.dodge.is_ready())

	# every damage source respects the i-frames
	await _reset()
	var trap := _room.OBJECT_SCENES[2].instantiate() as EnvObject
	trap.global_position = _player.global_position + Vector2(0, -40)
	_room.objects.add_child(trap)
	await _frames(2)
	_player.aim_direction = Vector2.UP
	_player.dodge.try_dodge()
	await _seconds(Dodge.SECONDS)
	_check("dodging over an armed trap does not hurt", _player.hp == 100, "hp %d" % _player.hp)
	await _reset()
	var barrel := _room.OBJECT_SCENES[0].instantiate() as EnvObject
	barrel.global_position = _player.global_position + Vector2(60, 0)
	_room.objects.add_child(barrel)
	await _frames(2)
	_player.aim_direction = Vector2.DOWN
	_player.dodge.try_dodge()
	barrel.detonate()
	_check("a barrel blast mid-dodge does not hurt", _player.hp == 100, "hp %d" % _player.hp)


## A bullet aimed straight at the knight, from the left, at his middle.
func _incoming() -> EnemyBullet:
	var r := _hitbox()
	return _bullet(Vector2(r.position.x - 40.0, r.get_center().y), Vector2.RIGHT)


func _dodge_and_graze() -> void:
	# without a dodge: a hit, -10 HP and -25 meter
	await _reset()
	_meter.meter = 50
	var hit := _incoming()
	await _seconds(0.6)
	_check("standing still, the shot hits: -10 HP", _player.hp == 90, "hp %d" % _player.hp)
	_check("and costs 25 meter, no graze", _meter.meter == 25, "meter %d" % _meter.meter)
	if is_instance_valid(hit):
		hit.queue_free()

	# dodging through it: no damage, and it is a graze
	await _reset()
	var shot := _incoming()
	_player.aim_direction = Vector2.LEFT     # straight through it
	_player.dodge.try_dodge()
	await _seconds(0.8)
	_check("dodging through the shot: no damage", _player.hp == 100, "hp %d" % _player.hp)
	_check("the shot passes through instead of breaking", is_instance_valid(shot)
			and shot.global_position.x > _player.global_position.x + 40.0)
	_check("and pays a graze, +5", _meter.meter == GrazeMeter.METER_GAIN_PER_GRAZE, "meter %d" % _meter.meter)
	if is_instance_valid(shot):
		shot.queue_free()

	# still inside him when the i-frames run out: it hits then
	await _reset()
	_player.aim_direction = Vector2.LEFT
	_player.dodge.try_dodge()
	await _seconds(Dodge.SECONDS + 0.02)      # moving done, i-frames left
	var r := _hitbox()
	var late := _bullet(r.get_center(), Vector2.RIGHT)
	await _seconds(0.25)
	_check("a shot still inside him when the i-frames end hits him", _player.hp == 90,
			"hp %d, bullet alive %s" % [_player.hp, str(is_instance_valid(late))])
	_check("and does not pay a graze", _meter.meter == 0, "meter %d" % _meter.meter)

	# grazing still works the ordinary way: a near miss, no dodge
	await _reset()
	var r2 := _hitbox()
	var near := _bullet(Vector2(r2.position.x - 80.0, r2.end.y + 12.0), Vector2.RIGHT)
	await _seconds(1.2)
	_check("an ordinary near miss still grazes", _meter.meter == 5 and _player.hp == 100,
			"meter %d hp %d" % [_meter.meter, _player.hp])
	if is_instance_valid(near):
		near.queue_free()


func _shadow_step() -> void:
	await _reset()
	_player.loadout.add_item("shadow_step")
	_player.aim_direction = Vector2.LEFT
	var start := _player.global_position
	_player.dodge.try_dodge()
	await _seconds(Items.SHADOW_STEP_SECONDS + 0.05)
	var moved := _player.global_position.distance_to(start)
	_check("Shadow Step: the dodge goes about 160 px", absf(moved - Items.SHADOW_STEP_DISTANCE_PX) < 20.0, "%.0f px" % moved)
	_check("with longer i-frames", _player.is_phasing())
	await _seconds(Items.SHADOW_STEP_COOLDOWN - Items.SHADOW_STEP_SECONDS + 0.05)
	_check("and recovers in %.1f s" % Items.SHADOW_STEP_COOLDOWN, _player.dodge.is_ready())
