extends Node2D
## A thrown Blot Bomb: arcs from `from` to `to`, then bursts. NOT IN THE GDD.
##
## The burst damages enemies (source "player", so normal energy), detonates
## every barrel in range the way the Shockwave does, and is one hit on cover.
## That is the hook into Environmental Combat: bomb a barrel next to a crowd
## and the barrel's own kills still pay double.

var from: Vector2
var to: Vector2
var _t: float = 0.0
var _body: Polygon2D
var _shadow: Polygon2D


func _ready() -> void:
	z_index = 6
	_shadow = Polygon2D.new()
	_shadow.polygon = _ellipse(8, 4)
	_shadow.color = Color(0, 0, 0, 0.45)
	add_child(_shadow)
	_body = Polygon2D.new()
	_body.polygon = _ellipse(8, 8)
	_body.color = Palette.INK
	add_child(_body)
	# A Gilt rim and a short fuse, so the bomb reads against a dark floor.
	var rim := Line2D.new()
	rim.width = 2.0
	rim.default_color = Palette.GILT
	rim.closed = true
	for p in _ellipse(8, 8):
		rim.add_point(p)
	_body.add_child(rim)
	var fuse := Line2D.new()
	fuse.width = 2.0
	fuse.default_color = Palette.EMBER
	fuse.add_point(Vector2(4, -6))
	fuse.add_point(Vector2(8, -11))
	_body.add_child(fuse)
	var glint := Polygon2D.new()
	glint.polygon = _ellipse(2, 2)
	glint.position = Vector2(-2, -2)
	glint.color = Palette.GILT
	_body.add_child(glint)
	global_position = from


func _physics_process(delta: float) -> void:
	_t += delta / Items.BOMB_FLIGHT_SECONDS
	var k := minf(_t, 1.0)
	global_position = from.lerp(to, k)
	_shadow.position = Vector2.ZERO
	_body.position = Vector2(0, -sin(k * PI) * 60.0)
	_body.rotation += delta * 10.0
	if _t >= 1.0:
		_burst()


func _burst() -> void:
	set_physics_process(false)
	var at := global_position
	for e in get_tree().get_nodes_in_group("enemy"):
		if e is Enemy and (e as Enemy).global_position.distance_to(at) <= Items.BOMB_RADIUS_PX:
			(e as Enemy).take_damage(Items.BOMB_DAMAGE, "player")
	for o in get_tree().get_nodes_in_group("env_object"):
		if not (o is EnvObject) or (o as EnvObject).global_position.distance_to(at) > Items.BOMB_RADIUS_PX:
			continue
		var env := o as EnvObject
		if env.kind == EnvObject.Kind.BARREL:
			env.detonate()          # like the Shockwave: a bomb sets a barrel off
		else:
			env.take_hit("player")  # one hit on cover
	if GameManager.instance:
		GameManager.instance.shake(4.0)
	# Ink splash: a dark blot that spreads and fades, ringed in Gilt so it
	# reads as the player's, not as a hazard.
	_body.visible = false
	_shadow.visible = false
	var blot := Polygon2D.new()
	blot.polygon = _ellipse(Items.BOMB_RADIUS_PX, Items.BOMB_RADIUS_PX * 0.7)
	blot.color = Color(Palette.INK, 0.6)
	add_child(blot)
	var ring := Line2D.new()
	ring.width = 3.0
	ring.default_color = Palette.GILT
	ring.closed = true
	for p in _ellipse(Items.BOMB_RADIUS_PX, Items.BOMB_RADIUS_PX * 0.7):
		ring.add_point(p)
	add_child(ring)
	scale = Vector2(0.2, 0.2)
	var t := create_tween().set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate:a", 0.0, 0.5).set_delay(0.15)
	t.chain().tween_callback(queue_free)


func _ellipse(rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts
