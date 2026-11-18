extends Area2D
## One of the Warding Pages: orbits the knight (Loadout moves it) and eats
## any enemy bullet it touches, then rests for WARD_RECHARGE_SECONDS.
## Like Isaac's orbitals, it is a shield the player has to aim with their
## body. NOT IN THE GDD.

const RADIUS_PX := 10.0

var _rest: float = 0.0
var _sprite: Polygon2D


func _ready() -> void:
	collision_layer = 0
	collision_mask = 8          # enemy_bullet
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = RADIUS_PX
	shape.shape = circle
	add_child(shape)
	# A small parchment page with an ink edge.
	var edge := Polygon2D.new()
	edge.polygon = PackedVector2Array([Vector2(-8, -10), Vector2(8, -10), Vector2(8, 10), Vector2(-8, 10)])
	edge.color = Palette.INK
	add_child(edge)
	_sprite = Polygon2D.new()
	_sprite.polygon = PackedVector2Array([Vector2(-6, -8), Vector2(6, -8), Vector2(6, 8), Vector2(-6, 8)])
	_sprite.color = Palette.PARCHMENT
	add_child(_sprite)
	for y in [-4.0, 0.0, 4.0]:
		var line := Line2D.new()
		line.width = 1.0
		line.default_color = Palette.INK_VIOLET
		line.add_point(Vector2(-4, y))
		line.add_point(Vector2(4, y))
		add_child(line)
	z_index = 4
	area_entered.connect(_on_area_entered)


func _physics_process(delta: float) -> void:
	rotation += delta * 3.0
	if _rest > 0.0:
		_rest -= delta
		if _rest <= 0.0:
			modulate.a = 1.0


func _on_area_entered(area: Area2D) -> void:
	if _rest > 0.0 or not (area is EnemyBullet):
		return
	area.queue_free()
	_rest = Items.WARD_RECHARGE_SECONDS
	modulate.a = 0.3
