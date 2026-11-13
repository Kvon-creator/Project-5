class_name RoomLayouts
extends RefCounted
## Reads assets/sprites/rooms/layouts.json - the pool of room layouts.
##
## GDD, Room-Based Combat: "Layouts: Drawn at random from a pool of 10
## hand-built layouts, no repeats in a run".
##
## Why this is so small: every room image conforms to one shared framing (see
## docs/ROOM_BRIEF.md), so the floor outline, the doors and the spawn markers
## are IDENTICAL across all ten. Switching layouts is therefore a texture
## swap - no collision to rebuild, no markers to move. Getting the art to
## conform is what buys that simplicity.

const MANIFEST_PATH := "res://assets/sprites/rooms/layouts.json"
const ROOMS_DIR := "res://assets/sprites/rooms/"


## Every layout in the pool, as [{name, image, source}, ...].
## Empty if the manifest is missing or malformed - callers should cope.
static func all() -> Array:
	if not FileAccess.file_exists(MANIFEST_PATH):
		push_warning("RoomLayouts: %s not found." % MANIFEST_PATH)
		return []
	var text := FileAccess.get_file_as_string(MANIFEST_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("RoomLayouts: %s is not valid JSON." % MANIFEST_PATH)
		return []
	var rooms: Variant = parsed.get("rooms", [])
	return rooms if typeof(rooms) == TYPE_ARRAY else []


static func count() -> int:
	return all().size()


## The shared framing block: floor outline, doors and markers every room
## conforms to unless its own entry overrides them.
static func framing() -> Dictionary:
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var f: Variant = parsed.get("framing", {})
	return f if typeof(f) == TYPE_DICTIONARY else {}


## One layout's manifest entry, or {} if out of range.
static func entry(index: int) -> Dictionary:
	var rooms := all()
	if index < 0 or index >= rooms.size():
		return {}
	var e: Variant = rooms[index]
	return e if typeof(e) == TYPE_DICTIONARY else {}


## The geometry a layout actually uses: the shared framing, with any keys the
## room's own entry overrides (a painted room whose floor is not the shared
## rectangle lists its own floor_polygon, doors and markers).
static func geometry_for(index: int) -> Dictionary:
	var g := framing().duplicate(true)
	var e := entry(index)
	for key in ["floor_polygon", "floor_centre", "doors", "spawn_markers", "object_markers", "fixtures", "title"]:
		if e.has(key):
			g[key] = e[key]
	return g


## The background texture for one layout, or null if it will not load.
static func texture_for(index: int) -> Texture2D:
	var rooms := all()
	if index < 0 or index >= rooms.size():
		return null
	var path: String = ROOMS_DIR + str(rooms[index].get("image", ""))
	if not ResourceLoader.exists(path):
		push_warning("RoomLayouts: missing image %s" % path)
		return null
	return load(path) as Texture2D


## An index not in `used`. Returns -1 only when the pool is empty.
##
## When every layout has been used it starts over rather than failing: the
## GDD asks for no repeats in a RUN of 8 rooms, and the pool is meant to be
## 10, so this only matters while the pool is still being filled in.
static func draw_unused(used: Array) -> int:
	var rooms := all()
	if rooms.is_empty():
		return -1
	# Never draw the boss arena for an ordinary room, and keep the Blender
	# stand-ins for after every painted room has been seen.
	var available: Array[int] = []
	var standins: Array[int] = []
	for i in rooms.size():
		if i in used or _flag(rooms[i], "boss") or _flag(rooms[i], "elite"):
			continue
		if _flag(rooms[i], "standin"):
			standins.append(i)
		else:
			available.append(i)
	if available.is_empty():
		available = standins
	if available.is_empty():
		return randi() % rooms.size()
	return available[randi() % available.size()]


## The layout tagged `"boss": true`, or -1 if none is.
static func boss_layout() -> int:
	return tagged_layout("boss")


## The first layout carrying `tag: true` ("boss", "elite"), or -1.
static func tagged_layout(tag: String) -> int:
	var rooms := all()
	for i in rooms.size():
		if _flag(rooms[i], tag):
			return i
	return -1


static func _flag(entry: Variant, key: String) -> bool:
	return typeof(entry) == TYPE_DICTIONARY and bool(entry.get(key, false))
