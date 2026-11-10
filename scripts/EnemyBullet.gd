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

signal grazed_once
signal hit_player(damage: int)

## Set by GrazeMeter when this bullet has paid out. GDD: "Each bullet can be
## grazed once."
var grazed: bool = false:
	set(value):
		if value and not grazed:
			grazed = true
			_show_grazed()
			grazed_once.emit()
		else:
			grazed = value

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


func _physics_process(delta: float) -> void:
	# Built: bullets fly. This is visual, not mechanical - the patterns that
	# decide WHERE they fly are the enemy's job.
	global_position += direction * SPEED_PX_PER_SECOND * delta


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		hit_player.emit(DAMAGE)
		# TODO(Jarman): call body.take_damage(DAMAGE) and queue_free().
		# Player.take_damage already handles the -25 meter penalty via its
		# took_damage signal, so there is nothing to do here about grazing.
	pass


## A grazed bullet gets a faint Graze Gold core, so the player can see which
## bullets they have already banked. It stays Hostile Magenta overall - the
## palette rule is absolute - but the centre shifts enough to read.
func _show_grazed() -> void:
	var tween := create_tween()
	tween.tween_property(sprite, "self_modulate",
			Palette.ENEMY_BULLET.lerp(Palette.GRAZE_GOLD, 0.35), 0.08)
