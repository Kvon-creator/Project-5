extends Node
## Ember Ink's burn, attached to an enemy as a child named "Burn".
## BURN_TICKS ticks of BURN_TICK_DAMAGE, one every BURN_TICK_SECONDS. A fresh
## hit restarts the count rather than stacking. NOT IN THE GDD.
##
## The damage source is "player": a burn kill pays normal energy. Only barrel
## and trap kills pay double, per the GDD cross-link.

var _ticks_left: int = 0
var _clock: float = 0.0


func ignite() -> void:
	_ticks_left = Items.BURN_TICKS
	_clock = Items.BURN_TICK_SECONDS
	_tint(true)


func _physics_process(delta: float) -> void:
	if _ticks_left <= 0:
		return
	_clock -= delta
	if _clock > 0.0:
		return
	_clock = Items.BURN_TICK_SECONDS
	_ticks_left -= 1
	var e := get_parent() as Enemy
	if e == null or e.hp <= 0:
		return
	e.take_damage(Items.BURN_TICK_DAMAGE, "player")
	if _ticks_left <= 0:
		_tint(false)


func _tint(on: bool) -> void:
	var e := get_parent() as Enemy
	if e and is_instance_valid(e.sprite):
		e.sprite.self_modulate = Palette.EMBER.lightened(0.45) if on else Color.WHITE
