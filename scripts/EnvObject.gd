class_name EnvObject
extends StaticBody2D
## Mechanic 1: Environmental Combat. Barrel, Cover and Trap all use this.
##
## OWNER: K'von Gates. Due Dec 2.
## GDD architecture box: "EnvObject.gd / Barrel, Cover, Trap scenes /
## Environmental Combat: type, hits taken (0-5), trap armed".
## Reads: Enemy, Player ("Who is in the blast or on the trap").
##
## GDD input: "WASD to move, mouse to aim, left-click to shoot an object;
## traps trigger when stepped on."
##
## WHAT IS BUILT: everything in GDD section 1.
##   Barrel - lit after the first hit, detonates on the second (or at once
##            inside a Shockwave): 30 damage to every enemy within 96 px,
##            credited as a "barrel" kill so Combat Rewards pays double.
##            The blast also catches the player, chips cover and chains
##            other barrels.
##   Cover  - blocks enemy bullets, breaks on the 5th hit from any source
##            (player shots, enemy bullets, barrel blasts).
##   Trap   - 15 damage to whoever steps on an armed plate, credited as a
##            "trap" kill; re-arms after 2 s and fires again straight away
##            if someone is still standing on it.

enum Kind { BARREL, COVER, TRAP }

# --------------------------------------------------------------------------
# GDD numbers - section 1, Environmental Combat
# --------------------------------------------------------------------------

## "Explosive barrel: Detonates after 2 hits; 30 damage to enemies within
## 96 px (3 m)"
const BARREL_HITS_TO_DETONATE: int = 2
const BARREL_DAMAGE: int = 30
const BARREL_RADIUS_PX: float = 96.0

## "Destructible cover: Blocks enemy bullets; breaks after 5 hits from any
## source"
const COVER_HITS_TO_BREAK: int = 5

## "Trap: Triggers when stepped on: 15 damage to the enemy or player on it;
## re-arms after 2 s (proposed)"
const TRAP_DAMAGE: int = 15
const TRAP_REARM_SECONDS: float = 2.0

# --------------------------------------------------------------------------
# Signals
# --------------------------------------------------------------------------

signal detonated(at: Vector2, radius: float)
signal broke(at: Vector2)
signal trap_triggered(victim: Node2D)
signal armed_changed(armed: bool)

# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

@export var kind: Kind = Kind.BARREL

var hits_taken: int = 0
var trap_armed: bool = true

## True for a moment after a trap fires, so it can show the "just triggered"
## art - nibs wet with violet ink. Purely visual; the damage has already been
## dealt by then.
var _just_triggered: bool = false
var _detonated: bool = false
var _broken: bool = false

## How long the triggered art shows before the plate goes back to disarmed.
## Shorter than TRAP_REARM_SECONDS, so the player sees three distinct states:
## fired -> safe -> armed again.
const TRIGGERED_DISPLAY_SECONDS: float = 0.6

## Counts down from TRAP_REARM_SECONDS after a trap fires; 0 when armed.
var _rearm_remaining: float = 0.0

## The pulsing Ember tint on a barrel that is one hit from going up.
var _fuse_tween: Tween

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("env_object")
	if kind == Kind.TRAP:
		add_to_group("hazard")   # Enemy Adaptation looks for this group
	set_physics_process(false)   # only a disarmed trap needs the clock
	_refresh_visual()


## Any damage source calls this: the player's shots, enemy bullets, a barrel
## blast. `source` is "player", "enemy" or "barrel".
func take_hit(_source: String = "player") -> void:
	if _detonated or _broken or kind == Kind.TRAP:
		return   # spent objects take no more hits; traps are not destroyed
	hits_taken += 1
	_flash()
	_refresh_visual()

	match kind:
		Kind.BARREL:
			if hits_taken >= BARREL_HITS_TO_DETONATE:
				detonate()
			else:
				_light_fuse()
		Kind.COVER:
			if hits_taken >= COVER_HITS_TO_BREAK:
				_break_cover()


## True once a barrel has gone up or a tome stack has broken - it is on its
## way out of the scene and no longer part of the room.
func is_spent() -> bool:
	return _detonated or _broken


## The Defensive Tome Stack has taken its 5th hit.
##
## GDD: "Destructible cover - Blocks enemy bullets; breaks after 5 hits from
## any source." Breaking means it stops blocking, so collision comes off
## immediately rather than when the animation finishes - otherwise there is a
## window where the cover looks gone but still eats bullets.
func _break_cover() -> void:
	if kind != Kind.COVER or _broken:
		return
	_broken = true
	broke.emit(global_position)

	# Stop blocking NOW. Deferred because a body may be mid-collision with it
	# on this physics frame.
	set_deferred("collision_layer", 0)
	for child in get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			child.set_deferred("disabled", true)

	_play_pages_burst()
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(sprite, "modulate:a", 0.0, 0.30)
	tween.tween_property(sprite, "scale", sprite.scale * 0.92, 0.30)
	tween.chain().tween_callback(queue_free)


## A burst of manuscript pages. The cover IS a stack of tomes, so it comes
## apart into paper - which also tells the player at a glance that this piece
## of cover is gone rather than merely damaged.
func _play_pages_burst(count: int = 8) -> void:
	var parent := get_tree().current_scene
	if parent == null:
		return
	for i in count:
		var page := Polygon2D.new()
		page.polygon = PackedVector2Array([
			Vector2(-5, -4), Vector2(5, -4), Vector2(5, 4), Vector2(-5, 4)])
		page.color = Palette.PARCHMENT
		page.z_index = 5
		parent.add_child(page)
		page.global_position = global_position

		var angle := TAU * (float(i) / count) + randf_range(-0.3, 0.3)
		var distance := randf_range(26.0, 58.0)
		var target := global_position + Vector2(cos(angle), sin(angle)) \
				* distance

		var tween := page.create_tween()
		tween.set_parallel(true)
		tween.tween_property(page, "global_position", target, 0.42) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(page, "rotation", randf_range(-3.0, 3.0), 0.42)
		tween.tween_property(page, "modulate:a", 0.0, 0.42)
		tween.chain().tween_callback(page.queue_free)


## Called by take_hit, and directly by Shockwave.
## GDD cross-link, Daryl -> K'von (new): "Barrels inside the 150 px radius
## detonate at once, and the 50 px knockback can push enemies onto traps."
func detonate() -> void:
	if kind != Kind.BARREL or _detonated:
		return
	_detonated = true
	hits_taken = maxi(hits_taken, BARREL_HITS_TO_DETONATE)
	if _fuse_tween:
		_fuse_tween.kill()
	# Out of the way at once: a spent barrel blocks nothing.
	set_deferred("collision_layer", 0)
	detonated.emit(global_position, BARREL_RADIUS_PX)
	_play_explosion()
	if GameManager.instance:
		GameManager.instance.shake(6.0)

	var origin := global_position

	# "30 damage to enemies within 96 px". The source is "barrel", which is
	# what makes Combat Rewards pay double for a kill (cross-link, new).
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Enemy and (e as Enemy).global_position.distance_to(origin) <= BARREL_RADIUS_PX:
			(e as Enemy).take_damage(BARREL_DAMAGE, "barrel")

	# The GDD architecture has EnvObject "reading the player for trap and
	# blast damage": standing next to your own barrel costs the same 30.
	var gm := GameManager.instance
	if gm and is_instance_valid(gm.player) \
			and gm.player.global_position.distance_to(origin) <= BARREL_RADIUS_PX:
		gm.player.take_damage(BARREL_DAMAGE)

	# Cover "breaks after 5 hits from any source" - a blast is one hit.
	# Other barrels in the radius chain, a frame later so each ring reads.
	for o in get_tree().get_nodes_in_group("env_object"):
		if o == self or not (o is EnvObject):
			continue
		var other := o as EnvObject
		if other.global_position.distance_to(origin) > BARREL_RADIUS_PX:
			continue
		if other.kind == Kind.COVER:
			other.take_hit("barrel")
		elif other.kind == Kind.BARREL:
			other.detonate.call_deferred()


## One hit from detonating: the lamp pulses Ember so the player can read it.
func _light_fuse() -> void:
	if _fuse_tween or not is_instance_valid(sprite):
		return
	_fuse_tween = create_tween().set_loops()
	_fuse_tween.tween_property(sprite, "self_modulate", Palette.FIRE.lightened(0.35), 0.18)
	_fuse_tween.tween_property(sprite, "self_modulate", Color.WHITE, 0.18)


# --------------------------------------------------------------------------
# Trap
# --------------------------------------------------------------------------

## Something walked (or was knocked) onto the plate.
func _on_body_entered(body: Node2D) -> void:
	if kind != Kind.TRAP or not trap_armed:
		return
	_trigger_trap(body)


## GDD: "Triggers when stepped on: 15 damage to the enemy or player on it;
## re-arms after 2 s (proposed)". Everyone on the plate when it fires is
## "on it"; `first` is whoever set it off.
func _trigger_trap(first: Node2D) -> void:
	var victims: Array[Node2D] = [first]
	for body in _bodies_on_plate():
		if body not in victims:
			victims.append(body)

	trap_triggered.emit(first)
	_just_triggered = true
	_rearm_remaining = TRAP_REARM_SECONDS
	set_physics_process(true)
	set_armed(false)

	for body in victims:
		if body is Enemy:
			# "trap" as the source: a kill here pays double energy.
			(body as Enemy).take_damage(TRAP_DAMAGE, "trap")
		elif body is Player:
			(body as Player).take_damage(TRAP_DAMAGE)


## The re-arm clock. Only runs while the trap is disarmed.
func _physics_process(delta: float) -> void:
	if kind != Kind.TRAP or trap_armed:
		set_physics_process(false)
		return
	_rearm_remaining -= delta
	if _just_triggered \
			and _rearm_remaining <= TRAP_REARM_SECONDS - TRIGGERED_DISPLAY_SECONDS:
		_just_triggered = false
		_refresh_visual()
	if _rearm_remaining > 0.0:
		return
	_rearm_remaining = 0.0
	_just_triggered = false
	set_physics_process(false)
	set_armed(true)
	# Still standing on it when it re-arms? Then it has been stepped on.
	var still_on := _bodies_on_plate()
	if not still_on.is_empty():
		_trigger_trap(still_on[0])


## Living enemies and the player currently over the plate.
func _bodies_on_plate() -> Array[Node2D]:
	var out: Array[Node2D] = []
	var trigger := get_node_or_null("Trigger") as Area2D
	if trigger == null or not trigger.monitoring:
		return out
	for body in trigger.get_overlapping_bodies():
		if body is Enemy and (body as Enemy).hp > 0:
			out.append(body)
		elif body is Player and not (body as Player).is_dead:
			out.append(body)
	return out


func set_armed(value: bool) -> void:
	if trap_armed == value:
		return
	trap_armed = value
	armed_changed.emit(value)
	_refresh_visual()


# --------------------------------------------------------------------------
# Visuals - built
# --------------------------------------------------------------------------

## Swap to the texture matching the current state. Scenes carry their textures
## as node metadata, so this script never hard-codes an asset path.
func _refresh_visual() -> void:
	if not is_instance_valid(sprite):
		return
	var key := ""
	match kind:
		Kind.COVER:
			# Three stages across five hits: 0-1 intact, 2-3 cracked,
			# 4-5 crumbling. The player has to be able to read how close a
			# piece of cover is to breaking, because the GDD lets them
			# "trade cover for a Shockwave".
			if hits_taken <= 1:
				key = "texture_intact"
			elif hits_taken <= 3:
				key = "texture_cracked"
			else:
				key = "texture_crumbling"
		Kind.TRAP:
			if _just_triggered:
				key = "texture_triggered"
			else:
				key = "texture_armed" if trap_armed else "texture_disarmed"
		Kind.BARREL:
			key = "texture_barrel"
	if key != "" and sprite.has_meta(key):
		sprite.texture = sprite.get_meta(key)


func _flash() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Palette.BONE, 0.04)
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.10)


## An expanding Ember ring at exactly BARREL_RADIUS_PX, so the player can see
## the blast they are actually getting. Ember, per the palette
## ("Ember: Player accents, explosive barrels, fire").
func _play_explosion() -> void:
	var ring := Line2D.new()
	ring.width = 4.0
	ring.default_color = Palette.FIRE
	ring.z_index = 6
	for i in range(49):
		var a := TAU * float(i) / 48.0
		ring.add_point(Vector2(cos(a), sin(a)))
	get_tree().current_scene.add_child(ring)
	ring.global_position = global_position
	ring.scale = Vector2(0.1, 0.1)

	var tween := ring.create_tween()
	tween.set_parallel(true)
	tween.tween_property(ring, "scale",
			Vector2(BARREL_RADIUS_PX, BARREL_RADIUS_PX), 0.28) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(ring, "modulate:a", 0.0, 0.28)
	tween.chain().tween_callback(ring.queue_free)

	sprite.visible = false
	await get_tree().create_timer(0.3).timeout
	queue_free()
