extends Node
## Checks every equipment and power-up drop does what its blurb says.
## Not part of the game.
##
##   godot --headless --path . res://tests/ItemsTest.tscn
##
## Each case starts from an empty loadout on open floor with the room's own
## waves stopped, gives the knight one item, and measures the effect. Exits 0
## only if every check holds.

var _gm: GameManager
var _room: RoomManager
var _player: Player
var _passed := 0
var _failed := 0
var _c: Vector2          # open floor centre
var _aim := Vector2.RIGHT  # where the attack cases fire


func _ready() -> void:
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	Engine.max_physics_steps_per_frame = 32
	add_child(load("res://scenes/Main.tscn").instantiate())
	_gm = GameManager.instance
	_room = _gm.room
	_player = _gm.player
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


## `s` game seconds. Physics delta is scaled by Engine.time_scale, so a game
## second is fewer ticks than ticks_per_second.
func _seconds(s: float) -> void:
	await _frames(int(ceil(s * Engine.physics_ticks_per_second / Engine.time_scale)))


## A clean slate: no enemies, bullets, objects or pickups; a fresh loadout;
## full health; the knight at the centre of an open room.
func _reset() -> void:
	_room.stop()
	for group in ["enemy", "enemy_bullet", "player_bullet", "item_pickup", "familiar", "env_object"]:
		for n in get_tree().get_nodes_in_group(group):
			n.get_parent().remove_child(n)
			n.queue_free()
	_room.enemies_alive = 0
	if _player.loadout:
		_player.remove_child(_player.loadout)
		_player.loadout.queue_free()
	_player.loadout = Loadout.new()
	_player.add_child(_player.loadout)
	_player.hp = Player.MAX_HP
	_player.is_dead = false
	_player.is_invulnerable = false
	_player.set("_hit_timer", 0.0)
	_player.global_position = _c
	_player.aim_direction = Vector2.RIGHT
	_aim = Vector2.RIGHT
	# Player.gd re-aims at the mouse every frame; the attack cases switch
	# that off so a shot goes where the test points it.
	_player.set_physics_process(true)
	await _frames(3)


func _dummy(species: String, at: Vector2, frozen: bool = true) -> Enemy:
	var e := _room.ENEMY_SCENE.instantiate() as Enemy
	e.species = species
	e.global_position = at
	_room.enemies.add_child(e)
	if frozen:
		e.set_physics_process(false)
	return e


func _enemy_shot(at: Vector2, dir: Vector2) -> EnemyBullet:
	var b := load("res://scenes/EnemyBullet.tscn").instantiate() as EnemyBullet
	b.direction = dir
	b.global_position = at
	get_tree().current_scene.add_child(b)
	return b


func _run() -> void:
	# an open layout, so no tome wall sits in a line of fire
	for i in RoomLayouts.count():
		var e := RoomLayouts.entry(i)
		if (e.get("fixtures", []) as Array).is_empty() and not e.get("boss", false) \
				and not e.get("standin", false):
			_room.load_layout(i, false)
			break
	_c = _room._nearest_open_point(_room.floor_centre())
	_room.bake_navigation()

	await _catalogue()
	await _room_clear_choice()
	await _lives_and_hearts()
	await _attacks()
	await _abilities()
	print("\n%d passed, %d failed" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 else 1)


# --------------------------------------------------------------------------

func _catalogue() -> void:
	var missing: Array[String] = []
	for id in Items.ALL.keys():
		if Items.icon(id) == null or Items.hud_icon(id) == null:
			missing.append(id)
	_check("every item has a pickup sprite and a HUD icon", missing.is_empty(), str(missing))
	var ok := true
	for i in 50:
		var d := Items.draw(2, [], 0)
		if d.size() != 2 or d[0] == d[1] or "ink_heart" in d:
			ok = false
	_check("a draw gives distinct equipment, never a heart", ok)
	var all_but_two: Array = []
	for id in Items.ALL.keys():
		if Items.ALL[id]["unique"] and id != "split_nib":
			all_but_two.append(id)
	var d2 := Items.draw(5, all_but_two, Items.MAX_EXTRA_LIVES)
	_check("owned items and a full stock of lives leave the pool", d2 == ["split_nib"], str(d2))


func _room_clear_choice() -> void:
	await _reset()
	_gm.loot._on_room_cleared(1)
	await _frames(3)
	var picks := get_tree().get_nodes_in_group("item_pickup")
	_check("clearing a room offers a choice of two items", picks.size() == 2, "%d" % picks.size())
	if picks.size() != 2:
		return
	var a := picks[0] as ItemPickup
	var b := picks[1] as ItemPickup
	var far := true
	for p in picks:
		if (p as Node2D).global_position.distance_to(_player.global_position) < 30.0:
			far = false
	_check("the choice is laid out apart, on open floor",
			a.global_position.distance_to(b.global_position) >= 60.0
			and _room._is_open_floor(a.global_position, 8.0) and _room._is_open_floor(b.global_position, 8.0))
	var a_id := a.item_id
	var b_id := b.item_id
	_player.global_position = a.global_position
	await _frames(6)
	_check("walking over one takes it", _player.loadout.has(a_id) or a_id == "phoenix_seal" and _player.loadout.extra_lives == 1, a_id)
	await _seconds(0.5)
	_check("the other one crumbles away", not is_instance_valid(b) and not _player.loadout.has(b_id))
	_check("no more choices from the same room", get_tree().get_nodes_in_group("item_pickup").is_empty())
	var hp := _player.hp
	_gm.loot._on_room_cleared(RoomManager.BOSS_ROOM)
	await _frames(3)
	_check("beating the boss drops nothing", get_tree().get_nodes_in_group("item_pickup").is_empty() and _player.hp == hp)


func _lives_and_hearts() -> void:
	await _reset()
	var died := [0]
	var on_died := func() -> void: died[0] += 1
	_player.died.connect(on_died)
	# the run must not end in the middle of the test
	_player.died.disconnect(_gm._on_player_died)
	_player.loadout.add_item("phoenix_seal")
	_check("Phoenix Seal: +1 life", _player.loadout.extra_lives == 1)
	var shot := _enemy_shot(_c + Vector2(100, 0), Vector2.LEFT)
	_player.hp = 10
	_player.take_damage(10)
	_check("a lethal hit spends the life and revives at 50 HP",
			died[0] == 0 and _player.hp == Items.REVIVE_HP and _player.loadout.extra_lives == 0,
			"hp %d lives %d died %d" % [_player.hp, _player.loadout.extra_lives, died[0]])
	await _frames(2)
	_check("the revive clears nearby enemy shots", not is_instance_valid(shot))
	_player.take_damage(10)
	_check("the knight is untouchable just after a revive", _player.hp == Items.REVIVE_HP)
	await _seconds(Items.REVIVE_INVULNERABLE_SECONDS + 0.1)
	_player.hp = 10
	_player.take_damage(10)
	_check("with no lives left, a lethal hit is a death", died[0] == 1)
	_player.died.disconnect(on_died)
	_player.died.connect(_gm._on_player_died)

	await _reset()
	for i in 5:
		_player.loadout.add_item("phoenix_seal")
	_check("lives are capped at %d" % Items.MAX_EXTRA_LIVES, _player.loadout.extra_lives == Items.MAX_EXTRA_LIVES)

	await _reset()
	_player.hp = 40
	_player.loadout.add_item("ink_heart")
	_check("Heart of Ink heals 25", _player.hp == 65, "hp %d" % _player.hp)
	_player.hp = 90
	_player.loadout.add_item("ink_heart")
	_check("healing stops at 100", _player.hp == 100)
	_check("a heart is used, not kept", not _player.loadout.has("ink_heart"))


# --------------------------------------------------------------------------

func _fire_once() -> Array[PlayerBullet]:
	_player.set_physics_process(false)
	_player.aim_direction = _aim
	var before := get_tree().get_nodes_in_group("player_bullet")
	_player._fire()
	await _frames(1)
	var out: Array[PlayerBullet] = []
	for b in get_tree().get_nodes_in_group("player_bullet"):
		if b not in before:
			out.append(b as PlayerBullet)
	return out


## Bullets leave the nib 14 px above the knight's feet, and enemy hitboxes
## sit at their feet, so the test foes stand on that line.
func _attacks() -> void:
	await _reset()
	var plain := await _fire_once()
	_check("no equipment: one 10-damage shot", plain.size() == 1 and plain[0].damage == 10)

	await _reset()
	_player.loadout.add_item("split_nib")
	var fan := await _fire_once()
	var angles: Array[float] = []
	for b in fan:
		angles.append(rad_to_deg(b.direction.angle()))
	angles.sort()
	_check("Split Nib: three shots, 12 degrees apart, 5 damage each",
			fan.size() == 3 and fan[0].damage == 5 and absf(angles[2] - angles[0] - 24.0) < 0.5, str(angles))

	await _reset()
	_player.loadout.add_item("quickened_hand")
	var fs: float = _player.loadout.shot_pattern()["fire_scale"]
	_check("Quickened Hand: 35%% faster fire", absf(fs - 1.35) < 0.001, str(fs))

	await _reset()
	_player.loadout.add_item("leaden_nib")
	var heavy := await _fire_once()
	_check("Leaden Nib: 15 damage, bigger, slower fire",
			heavy[0].damage == 15 and heavy[0].size_scale > 1.0
			and absf(float(_player.loadout.shot_pattern()["fire_scale"]) - 0.8) < 0.001)

	# piercing: three snails in a line
	await _reset()
	_player.loadout.add_item("bodkin_nib")
	var line: Array[Enemy] = []
	for i in 3:
		line.append(_dummy("snail", _c + Vector2(80 + i * 45, -14)))
	await _frames(2)
	await _fire_once()
	await _seconds(0.6)
	_check("Bodkin Nib: one shot passes through all three in a line",
			line[0].hp == 30 and line[1].hp == 30 and line[2].hp == 30,
			"%d %d %d" % [line[0].hp, line[1].hp, line[2].hp])

	await _reset()
	var lone := _dummy("snail", _c + Vector2(80, -14))
	var behind := _dummy("snail", _c + Vector2(130, -14))
	await _frames(2)
	await _fire_once()
	await _seconds(0.6)
	_check("without it, the first one stops the shot", lone.hp == 30 and behind.hp == 40)

	# homing: the target is well off the line of fire
	await _reset()
	_player.loadout.add_item("seeking_ink")
	var off := _dummy("snail", _c + Vector2(200, 110))
	await _frames(2)
	await _fire_once()
	await _seconds(0.8)
	_check("Seeking Ink: a shot fired wide curves into the foe", off.hp == 30, "hp %d" % off.hp)
	await _reset()
	var off2 := _dummy("snail", _c + Vector2(200, 110))
	await _frames(2)
	await _fire_once()
	await _seconds(0.8)
	_check("without it, the same shot misses", off2.hp == 40)

	# ricochet: shoot straight up at the flat back wall, a foe behind the
	# knight (the side walls are slanted, so they would send it off at an angle)
	await _reset()
	_player.loadout.add_item("mirror_ink")
	_aim = Vector2.UP
	var back := _dummy("snail", _c + Vector2(0, 80))
	await _frames(2)
	var shots := await _fire_once()
	await _seconds(2.2)
	_check("Mirror Ink: a shot into the wall bounces back into the foe behind", back.hp < 40,
			"hp %d, bounces left %s" % [back.hp, str(shots[0].bounces) if is_instance_valid(shots[0]) else "-"])

	# burn
	await _reset()
	_player.loadout.add_item("ember_ink")
	var burning := _dummy("grotesque", _c + Vector2(90, -14))
	await _frames(2)
	await _fire_once()
	await _seconds(0.4)
	var after_hit := burning.hp
	await _seconds(Items.BURN_TICK_SECONDS * Items.BURN_TICKS + 0.3)
	_check("Ember Ink: the hit, then 4 burn ticks of 3", after_hit == 110 and burning.hp == 98,
			"after hit %d, after burn %d" % [after_hit, burning.hp])

	# chain lightning
	await _reset()
	_player.loadout.add_item("storm_quill")
	var first := _dummy("grotesque", _c + Vector2(90, -14))
	var second := _dummy("grotesque", _c + Vector2(90, 96))
	var too_far := _dummy("grotesque", _c + Vector2(90, -175))
	await _frames(2)
	await _fire_once()
	await _seconds(0.4)
	_check("Storm Quill: the hit arcs 5 damage to the nearest foe within 140 px",
			first.hp == 110 and second.hp == 115 and too_far.hp == 120,
			"%d %d %d" % [first.hp, second.hp, too_far.hp])


# --------------------------------------------------------------------------

func _abilities() -> void:
	# Shadow Step upgrades the dodge (tests/DodgeTest checks the dodge itself)
	await _reset()
	_check("Shadow Step: the dodge starts un-upgraded", not _player.dodge.upgraded())
	_player.loadout.add_item("shadow_step")
	_check("picking it up upgrades the dodge", _player.dodge.upgraded()
			and _player.dodge.cooldown_total() == Items.SHADOW_STEP_COOLDOWN)

	# warding pages. The pages orbit inside the knight's own hitbox (his
	# whole sprite), so it is switched off here to watch the pages alone.
	await _reset()
	_player.loadout.add_item("warding_pages")
	var own_hitbox := _player.get_node("SpriteHitbox") as Area2D
	own_hitbox.monitorable = false
	await _frames(4)
	var pages: Array[Node2D] = []
	for w in _player.loadout.get_children():
		if w is Area2D:
			pages.append(w)
	_check("Warding Pages: two pages orbit the knight", pages.size() == 2
			and pages[0].global_position.distance_to(_player.global_position) > 30.0)
	var p0 := pages[0].global_position
	await _frames(6)
	_check("they move", pages[0].global_position.distance_to(p0) > 3.0)
	var caught := _enemy_shot(pages[0].global_position, Vector2.UP)
	await _frames(3)
	_check("a shot that touches a page is swallowed", not is_instance_valid(caught))
	_check("the page then rests, dimmed", pages[0].modulate.a < 1.0)
	var through := _enemy_shot(pages[0].global_position, Vector2.UP)
	await _frames(3)
	_check("a resting page lets the next shot through", is_instance_valid(through))
	if is_instance_valid(through):
		through.queue_free()
	await _seconds(Items.WARD_RECHARGE_SECONDS + 0.1)
	_check("and is back after %.1f s" % Items.WARD_RECHARGE_SECONDS, pages[0].modulate.a == 1.0)
	own_hitbox.monitorable = true

	# inkling
	await _reset()
	_player.loadout.add_item("inkling")
	var mark := _dummy("grotesque", _c + Vector2(0, -150))
	await _seconds(2.5)
	_check("Inkling: the familiar follows and shoots nearby foes", mark.hp < 120 and mark.hp % 5 == 0, "hp %d" % mark.hp)
	var fam := get_tree().get_nodes_in_group("familiar")
	_check("it stays near the knight", fam.size() == 1 and (fam[0] as Node2D).global_position.distance_to(_player.global_position) < 80.0)

	# blot bomb
	await _reset()
	_check("Blot Bomb does nothing until picked up", not _player.loadout.try_bomb(_c + Vector2(150, 0)))
	_player.loadout.add_item("blot_bomb")
	var near := _dummy("grotesque", _c + Vector2(100, 50))
	var safe := _dummy("snail", _c + Vector2(150, 160))
	var victim := _dummy("snail", _c + Vector2(270, -20))   # in the barrel's blast only
	victim.hp = 10
	var barrel := _room.OBJECT_SCENES[0].instantiate() as EnvObject
	barrel.global_position = _c + Vector2(190, -20)
	_room.objects.add_child(barrel)
	var went_off := [false]
	barrel.detonated.connect(func(_at: Vector2, _r: float) -> void: went_off[0] = true)
	var energy: Array = []
	var on_energy := func(amount: int, env: bool) -> void: energy.append([amount, env])
	CombatRewards.energy_awarded.connect(on_energy)
	await _frames(2)
	_check("Blot Bomb: E throws", _player.loadout.try_bomb(_c + Vector2(150, 0)))
	_check("only one at a time", not _player.loadout.try_bomb(_c + Vector2(150, 0)))
	await _seconds(Items.BOMB_FLIGHT_SECONDS + 0.2)
	_check("the burst deals 35 within 90 px", near.hp == 120 - 35 and safe.hp == 40, "near %d safe %d" % [near.hp, safe.hp])
	_check("and sets off a barrel in range", went_off[0])
	CombatRewards.energy_awarded.disconnect(on_energy)
	_check("the barrel's kill still pays double", [10, true] in energy, str(energy))
	_check("the knight is not hurt by his own bomb", _player.hp == 100)
	await _seconds(Items.BOMB_COOLDOWN_SECONDS)
	_check("ready again after 7 s", _player.loadout.try_bomb(_c + Vector2(-150, 0)))
