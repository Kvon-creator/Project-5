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
## WHAT IS BUILT: all three objects' visuals, including cover's three damage
## stages and the trap's armed/disarmed art, plus the hit bookkeeping that
## drives them.
## WHAT IS NOT: the blast, the bullet blocking, the trap trigger.

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

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("env_object")
	if kind == Kind.TRAP:
		add_to_group("hazard")   # Enemy Adaptation looks for this group
	_refresh_visual()


## Any damage source calls this: the player's shots, the Shockwave, a barrel
## blast. `source` is recorded so a chain reaction still credits correctly.
func take_hit(_source: String = "player") -> void:
	hits_taken += 1
	_flash()
	_refresh_visual()

	match kind:
		Kind.BARREL:
			if hits_taken >= BARREL_HITS_TO_DETONATE:
				detonate()
		Kind.COVER:
			if hits_taken >= COVER_HITS_TO_BREAK:
				_break_cover()
		Kind.TRAP:
			pass   # traps are not destroyed by damage


## Called by take_hit, and directly by Shockwave.
## GDD cross-link, Daryl -> K'von (new): "Barrels inside the 150 px radius
## detonate at once, and the 50 px knockback can push enemies onto traps."
func detonate() -> void:
	if kind != Kind.BARREL:
		return
	detonated.emit(global_position, BARREL_RADIUS_PX)
	_play_explosion()

	# TODO(K'von): deal BARREL_DAMAGE to every enemy within BARREL_RADIUS_PX,
	# passing "barrel" as the damage source so CombatRewards pays the double
	# energy. The player is in the blast too - the GDD does not exempt them.
	# Chain reaction: other barrels in the radius should take_hit() as well.


func _on_body_entered(body: Node2D) -> void:
	if kind != Kind.TRAP or not trap_armed:
		return
	trap_triggered.emit(body)
	set_armed(false)

	# TODO(K'von): deal TRAP_DAMAGE to `body`, with "trap" as the source.
	# "15 damage to the enemy or player on it" - both, not just enemies.

	# Built: the re-arm clock and its visual.
	await get_tree().create_timer(TRAP_REARM_SECONDS).timeout
	set_armed(true)


func set_armed(value: bool) -> void:
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
