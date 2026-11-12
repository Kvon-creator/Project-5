class_name PlayerBullet
extends Area2D
## The knight's shot.
##
## PREVIEW(Daryl): the smallest thing that makes shooting work. Flies
## straight, damages the first enemy it touches, chips cover and barrels, and
## dies on walls or after LIFETIME_SECONDS. Player.gd sets `direction` and
## `damage` before adding it to the scene.
##
## Palette: Nib Teal, per the GDD ("Player shots, nib glow, power-up").

const SPEED_PX_PER_SECOND: float = 520.0
const LIFETIME_SECONDS: float = 1.5

var direction: Vector2 = Vector2.RIGHT
var damage: int = 10

@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("player_bullet")
	rotation = direction.angle() + PI * 0.5
	sprite.modulate = Palette.PLAYER_SHOT
	z_index = 4
	body_entered.connect(_on_body_entered)
	get_tree().create_timer(LIFETIME_SECONDS).timeout.connect(queue_free)


func _physics_process(delta: float) -> void:
	global_position += direction * SPEED_PX_PER_SECOND * delta


func _on_body_entered(body: Node2D) -> void:
	if body is Enemy:
		(body as Enemy).take_damage(damage, "player")
	elif body is EnvObject:
		(body as EnvObject).take_hit("player")
	# Anything else that stops a bullet is a wall.
	queue_free()
