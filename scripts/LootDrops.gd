class_name LootDrops
extends Node
## When equipment and hearts appear. NOT IN THE GDD; numbers in Items.gd.
## Created by GameManager.
##
##   Room cleared (rooms 1-7)  ROOM_CLEAR_CHOICES items side by side at the
##                             room's centre; take one, the rest crumble.
##   Elite killed              ELITE_DROP_CHANCE of one item where it fell.
##   Standard enemy killed     STANDARD_HEART_CHANCE of a Heart of Ink, only
##                             while the knight is hurt.
##
## The GDD's own drop - Combat Rewards' damage shell every 5th kill - is
## separate and unchanged. These come on top of it.

## Off: nothing drops. tests/MechanicsTest turns it off so it checks the
## GDD's rules alone.
var enabled: bool = true

var _next_group: int = 1
var _room: RoomManager
var _player: Player


func setup(room: RoomManager, player: Player) -> void:
	_room = room
	_player = player
	room.room_cleared.connect(_on_room_cleared)
	room.enemy_spawned.connect(func(e: Enemy) -> void: e.died.connect(_on_enemy_died))


func _owned() -> Array:
	return _player.loadout.owned if _player and _player.loadout else []


func _lives() -> int:
	return _player.loadout.extra_lives if _player and _player.loadout else 0


func _on_room_cleared(room_index: int) -> void:
	if not enabled or room_index >= RoomManager.BOSS_ROOM:
		return   # the run is won
	var ids := Items.draw(Items.ROOM_CLEAR_CHOICES, _owned(), _lives())
	if ids.is_empty():
		return
	var centre := _room._nearest_open_point(_room.floor_centre())
	var group := _next_group
	_next_group += 1
	for i in ids.size():
		var offset := (i - (ids.size() - 1) * 0.5) * 90.0
		var at := _room._nearest_open_point(centre + Vector2(offset, 0))
		spawn(ids[i], at, group)


func _on_enemy_died(enemy: Enemy) -> void:
	if not enabled or enemy == null or not is_instance_valid(_player) or _player.is_dead:
		return
	match enemy.tier():
		"elite":
			if randf() < Items.ELITE_DROP_CHANCE:
				var ids := Items.draw(1, _owned(), _lives())
				if not ids.is_empty():
					spawn(ids[0], _clear_spot(enemy.global_position))
		"standard":
			if _player.hp < Player.MAX_HP and randf() < Items.STANDARD_HEART_CHANCE:
				spawn("ink_heart", _clear_spot(enemy.global_position))


func _clear_spot(p: Vector2) -> Vector2:
	return _room._nearest_open_point(p) if is_instance_valid(_room) else p


## Put an item on the floor. Deferred: a death is usually inside a physics
## callback, and an Area2D cannot join the tree then.
func spawn(id: String, at: Vector2, group: int = 0) -> ItemPickup:
	var p := ItemPickup.make(id)
	p.group_id = group
	p.position = at
	var parent: Node = _room.objects if is_instance_valid(_room) else get_tree().current_scene
	parent.add_child.call_deferred(p)
	return p
