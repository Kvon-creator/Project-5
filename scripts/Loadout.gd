class_name Loadout
extends Node2D
## What the knight has picked up this run: extra lives, abilities, and the
## changes to his shots. Created by Player.gd as a child, so it is wiped with
## the scene on restart - the GDD's "nothing carries over between runs".
##
## NOT IN THE GDD. See Items.gd for the catalogue and the numbers.
##
## Player.gd asks this node three things:
##   shot_pattern()  how many bullets, their spread, damage and fire rate
##   decorate(b)     give one PlayerBullet its properties (pierce, homing...)
##   try_revive()    spend a life instead of dying
## Abilities (dash, bomb, pages, inkling) run here.

signal item_added(id: String)
signal lives_changed(lives: int)
## For the HUD's ability slots. `remaining` is 0 when ready.
signal cooldown_changed(id: String, remaining: float, total: float)
signal revived

const FAMILIAR_SCRIPT := preload("res://scripts/Familiar.gd")
const WARD_SCRIPT := preload("res://scripts/WardPage.gd")
const BOMB_SCRIPT := preload("res://scripts/InkBomb.gd")

var owned: Array[String] = []
var extra_lives: int = 0

var _dash_cd: float = 0.0
var _bomb_cd: float = 0.0
var _dash_time: float = 0.0
var _dash_dir: Vector2 = Vector2.ZERO
var _afterimage_t: float = 0.0
var _wards: Array[Node2D] = []
var _ward_angle: float = 0.0

@onready var player: Player = get_parent() as Player


func has(id: String) -> bool:
	return id in owned


## Pick something up. Consumables act at once and are not kept.
func add_item(id: String) -> void:
	if not Items.exists(id):
		push_warning("Loadout: unknown item %s" % id)
		return
	match Items.kind(id):
		Items.Kind.CONSUMABLE:
			if id == "ink_heart":
				player.heal(Items.HEART_HEAL)
			item_added.emit(id)
			return
		Items.Kind.LIFE:
			extra_lives = mini(extra_lives + 1, Items.MAX_EXTRA_LIVES)
			lives_changed.emit(extra_lives)
	if id not in owned or Items.kind(id) == Items.Kind.LIFE:
		owned.append(id)
	match id:
		"warding_pages":
			_spawn_wards()
		"inkling":
			_spawn_familiar()
		"shadow_step":
			cooldown_changed.emit(id, 0.0, Items.DASH_COOLDOWN_SECONDS)
		"blot_bomb":
			cooldown_changed.emit(id, 0.0, Items.BOMB_COOLDOWN_SECONDS)
	item_added.emit(id)


# --------------------------------------------------------------------------
# Shots
# --------------------------------------------------------------------------

## {count, spread_deg, damage_scale, fire_scale}. Player.gd multiplies its GDD
## numbers (10 damage, 6 shots/s) by these.
func shot_pattern() -> Dictionary:
	var p := {"count": 1, "spread_deg": 0.0, "damage_scale": 1.0, "fire_scale": 1.0}
	if has("split_nib"):
		p["count"] = Items.SPLIT_SHOTS
		p["spread_deg"] = Items.SPLIT_SPREAD_DEG
		p["damage_scale"] *= Items.SPLIT_DAMAGE_SCALE
	if has("quickened_hand"):
		p["fire_scale"] *= Items.RAPID_FIRE_SCALE
	if has("leaden_nib"):
		p["damage_scale"] *= Items.HEAVY_DAMAGE_SCALE
		p["fire_scale"] *= Items.HEAVY_FIRE_SCALE
	return p


## Hand one bullet the properties the knight's equipment gives it.
func decorate(bullet: PlayerBullet) -> void:
	if has("bodkin_nib"):
		bullet.pierce = Items.PIERCE_COUNT
	if has("seeking_ink"):
		bullet.homing = true
	if has("mirror_ink"):
		bullet.bounces = Items.RICOCHET_BOUNCES
	if has("ember_ink"):
		bullet.burns = true
	if has("storm_quill"):
		bullet.chains = true
	if has("leaden_nib"):
		bullet.knockback_px = Items.HEAVY_KNOCKBACK_PX
		bullet.size_scale = 1.4


# --------------------------------------------------------------------------
# Extra lives
# --------------------------------------------------------------------------

## Called by Player.take_damage when HP hits 0. True if a life was spent.
func try_revive() -> bool:
	if extra_lives <= 0:
		return false
	extra_lives -= 1
	var i := owned.find("phoenix_seal")
	if i >= 0:
		owned.remove_at(i)
	lives_changed.emit(extra_lives)
	# Clear the bullets that killed him, the way the Shockwave does, so the
	# revive is not an instant second death.
	for b in get_tree().get_nodes_in_group("enemy_bullet"):
		if b is Node2D and (b as Node2D).global_position.distance_to(player.global_position) \
				<= Items.REVIVE_CLEAR_RADIUS_PX:
			b.queue_free()
	_play_ring(Palette.EMBER, Items.REVIVE_CLEAR_RADIUS_PX)
	revived.emit()
	return true


# --------------------------------------------------------------------------
# Abilities
# --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if player == null or player.is_dead:
		return
	if event.is_action_pressed("dash"):
		try_dash()
	elif event.is_action_pressed("ability"):
		try_bomb(get_global_mouse_position())


func is_dashing() -> bool:
	return _dash_time > 0.0


## The velocity Player.gd should use this frame while a dash is on.
func dash_velocity() -> Vector2:
	return _dash_dir * (Items.DASH_DISTANCE_PX / Items.DASH_SECONDS)


## Shadow Step: along the move input, or the aim if standing still.
func try_dash() -> bool:
	if not has("shadow_step") or _dash_cd > 0.0 or is_dashing():
		return false
	var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if dir == Vector2.ZERO:
		dir = player.aim_direction
	_dash_dir = dir.normalized()
	_dash_time = Items.DASH_SECONDS
	_dash_cd = Items.DASH_COOLDOWN_SECONDS
	player.grant_mercy(Items.DASH_INVULNERABLE_SECONDS)
	return true


## Blot Bomb: thrown at `target`, at most BOMB_THROW_MAX_PX away.
func try_bomb(target: Vector2) -> bool:
	if not has("blot_bomb") or _bomb_cd > 0.0:
		return false
	_bomb_cd = Items.BOMB_COOLDOWN_SECONDS
	var from := player.global_position + Vector2(0, -14)
	var to := target
	if from.distance_to(to) > Items.BOMB_THROW_MAX_PX:
		to = from + (to - from).normalized() * Items.BOMB_THROW_MAX_PX
	var bomb := Node2D.new()
	bomb.set_script(BOMB_SCRIPT)
	bomb.set("from", from)
	bomb.set("to", to)
	get_tree().current_scene.add_child(bomb)
	return true


func _physics_process(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd = maxf(0.0, _dash_cd - delta)
		cooldown_changed.emit("shadow_step", _dash_cd, Items.DASH_COOLDOWN_SECONDS)
	if _bomb_cd > 0.0:
		_bomb_cd = maxf(0.0, _bomb_cd - delta)
		cooldown_changed.emit("blot_bomb", _bomb_cd, Items.BOMB_COOLDOWN_SECONDS)
	if _dash_time > 0.0:
		_dash_time -= delta
		_afterimage_t -= delta
		if _afterimage_t <= 0.0:
			_afterimage_t = 0.03
			_afterimage()
	if not _wards.is_empty():
		_ward_angle += Items.WARD_SPIN_RAD_PER_S * delta
		for i in _wards.size():
			var a := _ward_angle + TAU * i / _wards.size()
			# Flattened orbit, to sit in the 3/4 view.
			_wards[i].position = Vector2(cos(a), sin(a) * 0.7) * Items.WARD_ORBIT_PX + Vector2(0, -16)


func _spawn_wards() -> void:
	for i in Items.WARD_COUNT:
		var w := Area2D.new()
		w.set_script(WARD_SCRIPT)
		add_child(w)
		_wards.append(w)


func _spawn_familiar() -> void:
	var f := Node2D.new()
	f.set_script(FAMILIAR_SCRIPT)
	f.set("owner_player", player)
	get_tree().current_scene.add_child.call_deferred(f)
	f.set_deferred("global_position", player.global_position + Vector2(-30, -20))


## A fading copy of the knight's current frame, behind him.
func _afterimage() -> void:
	var src := player.sprite
	if src == null or src.sprite_frames == null:
		return
	var ghost := Sprite2D.new()
	ghost.texture = src.sprite_frames.get_frame_texture(src.animation, src.frame)
	ghost.flip_h = src.flip_h
	ghost.offset = src.offset
	ghost.global_position = src.global_position
	ghost.scale = src.global_scale
	ghost.modulate = Color(Palette.NIB_TEAL, 0.45)
	ghost.z_index = 3
	get_tree().current_scene.add_child(ghost)
	var t := ghost.create_tween()
	t.tween_property(ghost, "modulate:a", 0.0, 0.22)
	t.tween_callback(ghost.queue_free)


func _play_ring(colour: Color, radius: float) -> void:
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = colour
	ring.z_index = 6
	for i in 49:
		var a := TAU * i / 48.0
		ring.add_point(Vector2(cos(a), sin(a)))
	get_tree().current_scene.add_child(ring)
	ring.global_position = player.global_position
	ring.scale = Vector2(0.1, 0.1)
	var t := ring.create_tween().set_parallel(true)
	t.tween_property(ring, "scale", Vector2(radius, radius), 0.4) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(ring, "modulate:a", 0.0, 0.5)
	t.chain().tween_callback(ring.queue_free)
