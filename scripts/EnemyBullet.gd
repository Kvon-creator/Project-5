class_name EnemyBullet
extends Area2D
## Enemy projectile.
##
## OWNER: Jarman (proposed), by Nov 18.
## GDD architecture box: "EnemyBullet.gd / EnemyBullet.tscn / damage 10,
## grazed flag".
##
## Two other mechanics read this script, so its two fields matter more than
## its size suggests:
##   GrazeMeter - "Grazed flag and distance"
##   Shockwave  - "bullets, enemies and barrels in 150 px"
##
## ART RULE, the GDD's strictest:
##     Hostile Magenta appears on enemy bullets and nothing else, so bullets
##     always read against the room.
## This is the only script in the project allowed to use Palette.HOSTILE_MAGENTA.

## "Enemy bullet damage 10 (10 hits from full HP)"
const DAMAGE: int = 10

## Proposed - the GDD does not give a bullet speed. Slow enough that a 20 px
## graze window is a real decision rather than a reflex, which is the whole
## point of Daryl's mechanic.
const SPEED_PX_PER_SECOND: float = 260.0
## Layers 5 (env_object) and 6 (wall).
const COVER_AND_WALLS: int = 16 | 32

## PREVIEW(Jarman): a bullet that misses everything still has to go away.
const LIFETIME_SECONDS: float = 4.0

signal grazed_once
signal hit_player(damage: int)

## Set by GrazeMeter when this bullet has paid out. GDD: "Each bullet can be
## grazed once."
## Backing field. A property setter must never assign to its OWN property:
## in Godot 4 that re-enters the setter and recurses until the stack blows.
## The first version of this did exactly that, so the first grazed bullet
## would have crashed the game inside Daryl's core mechanic.
var _grazed: bool = false

var grazed: bool:
	get:
		return _grazed
	set(value):
		if value == _grazed:
			return
		_grazed = value
		if value:
			_show_grazed()
			grazed_once.emit()

var direction: Vector2 = Vector2.RIGHT

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("enemy_bullet")
	# The sprite is rendered pointing along -Y with a tail, so rotating the
	# whole node to the heading gives every direction from one frame.
	rotation = direction.angle() + PI * 0.5
	# Belt and braces on the palette rule: whatever the scene file says, an
	# enemy bullet leaves here Hostile Magenta.
	sprite.modulate = Palette.ENEMY_BULLET
	z_index = 4
	# Hits the player's SpriteHitbox (the rectangle around the knight's
	# sprite), plus cover and walls as bodies. Not the player's body: that is
	# only the small circle at his feet.
	collision_mask = COVER_AND_WALLS | SpriteHitbox.PLAYER_LAYER
	area_entered.connect(_on_area_entered)
	area_exited.connect(_on_area_exited)
	get_tree().create_timer(LIFETIME_SECONDS).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	# Passing through a dodging knight: if his i-frames run out while this
	# bullet is still inside him, it hits him now.
	if _inside != null and is_instance_valid(_inside) and not _inside.is_phasing():
		_hit_player(_inside)
		return
	# Built: bullets fly. This is visual, not mechanical - the patterns that
	# decide WHERE they fly are the enemy's job.
	global_position += direction * SPEED_PX_PER_SECOND * delta


var _spent: bool = false
## The knight, while this bullet is passing through him mid-dodge.
var _inside: Player = null


## Cover and walls. (The player's body is no longer on this bullet's mask,
## but a Player passed in directly still counts as a hit, so callers and
## tests that simulate a hit this way keep working.)
func _on_body_entered(body: Node2D) -> void:
	if _spent:
		return
	if body is Player:
		_hit_player(body as Player)
		return
	_spent = true
	if body is EnvObject:
		# GDD: cover "breaks after 5 hits from any source".
		(body as EnvObject).take_hit("enemy")
	queue_free()


## The player's hitbox. During a dodge's i-frames the bullet passes through
## him instead (Dodge.gd), and stays live so the graze band can still pay
## out for it when it leaves.
func _on_area_entered(area: Area2D) -> void:
	if not (area is SpriteHitbox) or not ((area as SpriteHitbox).body is Player):
		return
	var player := (area as SpriteHitbox).body as Player
	if player.is_phasing():
		_inside = player
		return
	_hit_player(player)


func _on_area_exited(area: Area2D) -> void:
	if area is SpriteHitbox and (area as SpriteHitbox).body == _inside:
		_inside = null


func _hit_player(player: Player) -> void:
	if _spent:
		return
	_spent = true
	hit_player.emit(DAMAGE)
	# PREVIEW(Jarman). Player.take_damage already handles the -25 meter
	# penalty via its took_damage signal.
	player.take_damage(DAMAGE)
	queue_free()


## A grazed bullet gets a faint Graze Gold core, so the player can see which
## bullets they have already banked. It stays Hostile Magenta overall - the
## palette rule is absolute - but the centre shifts enough to read.
func _show_grazed() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "self_modulate",
			Palette.ENEMY_BULLET.lerp(Palette.GRAZE_GOLD, 0.35), 0.08)
