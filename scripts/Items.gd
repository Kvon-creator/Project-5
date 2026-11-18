class_name Items
extends RefCounted
## The catalogue of equipment and power-up drops.
##
## NOT IN THE GDD. Every number here is proposed, for playtesting. The GDD's
## own drop (Combat Rewards' +20% damage shell, every 5th kill) is untouched
## and still lives in CombatRewards.gd and PowerUp.gd.
##
## Three kinds of equipment, plus healing, each with its own medallion shape
## so a drop can be read before its glyph can (art: pipeline/item_icons.py):
##
##   LIFE        round Ember seal     - an extra life
##   CONSUMABLE  small Blood Rust seal - heals on pickup, not kept
##   ABILITY     Gilt diamond         - a new thing the knight can do
##   ATTACK      Nib Teal hexagon     - changes how his shots behave
##
## Inspiration, by mechanic rather than by name or art: homing / piercing /
## bouncing / burning shots are the tear effects of The Binding of Isaac;
## chain lightning on hit is Zeus's attack boons in Hades; the dash with
## invulnerability is Enter the Gungeon's dodge roll and Hades' dash; the
## orbiting bullet blockers and the shooting familiar are Isaac's orbitals and
## familiars; the extra life is Gungeon's Clone and Isaac's 1-ups.

enum Kind { LIFE, CONSUMABLE, ABILITY, ATTACK }

const ICON_DIR := "res://assets/sprites/items/"

## id -> {name, blurb, kind, weight, unique}
## weight: relative chance in a random draw. unique: once owned, it leaves
## the pool for the rest of the run.
const ALL := {
	"phoenix_seal": {
		"name": "Phoenix Seal", "kind": Kind.LIFE, "weight": 2, "unique": false,
		"blurb": "+1 life. Falling revives you at half health.",
	},
	"ink_heart": {
		"name": "Heart of Ink", "kind": Kind.CONSUMABLE, "weight": 0, "unique": false,
		"blurb": "Restores 25 HP.",
	},
	"shadow_step": {
		"name": "Shadow Step", "kind": Kind.ABILITY, "weight": 4, "unique": true,
		"blurb": "SPACE: dash through danger, untouchable mid-step.",
	},
	"warding_pages": {
		"name": "Warding Pages", "kind": Kind.ABILITY, "weight": 4, "unique": true,
		"blurb": "Two pages orbit you and swallow enemy shots.",
	},
	"inkling": {
		"name": "Inkling", "kind": Kind.ABILITY, "weight": 4, "unique": true,
		"blurb": "A little ink imp follows you and fires at foes.",
	},
	"blot_bomb": {
		"name": "Blot Bomb", "kind": Kind.ABILITY, "weight": 4, "unique": true,
		"blurb": "E: hurl an ink bomb at the cursor. Sets off barrels.",
	},
	"split_nib": {
		"name": "Split Nib", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Shots fan into three, each a little weaker.",
	},
	"bodkin_nib": {
		"name": "Bodkin Nib", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Shots pierce through two foes.",
	},
	"seeking_ink": {
		"name": "Seeking Ink", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Shots curve toward the nearest foe.",
	},
	"mirror_ink": {
		"name": "Mirror Ink", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Shots bounce off walls twice.",
	},
	"ember_ink": {
		"name": "Ember Ink", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Shots set foes burning.",
	},
	"storm_quill": {
		"name": "Storm Quill", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Hits arc lightning to a nearby foe.",
	},
	"quickened_hand": {
		"name": "Quickened Hand", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "+35% fire rate.",
	},
	"leaden_nib": {
		"name": "Leaden Nib", "kind": Kind.ATTACK, "weight": 4, "unique": true,
		"blurb": "Heavier shots: +50% damage and knockback, slower fire.",
	},
}

# --------------------------------------------------------------------------
# Numbers (proposed, not in the GDD)
# --------------------------------------------------------------------------

## Extra lives
const MAX_EXTRA_LIVES: int = 3
const REVIVE_HP: int = 50
const REVIVE_INVULNERABLE_SECONDS: float = 2.0
const REVIVE_CLEAR_RADIUS_PX: float = 150.0   # same as the Shockwave

## Healing
const HEART_HEAL: int = 25

## Shadow Step (dash)
const DASH_DISTANCE_PX: float = 150.0
const DASH_SECONDS: float = 0.16
const DASH_INVULNERABLE_SECONDS: float = 0.28   # the dash plus a little after
const DASH_COOLDOWN_SECONDS: float = 0.9

## Warding Pages
const WARD_COUNT: int = 2
const WARD_ORBIT_PX: float = 52.0
const WARD_SPIN_RAD_PER_S: float = 2.6
const WARD_RECHARGE_SECONDS: float = 1.2      # a page that ate a shot rests

## Inkling
const FAMILIAR_FIRE_INTERVAL: float = 0.75
const FAMILIAR_DAMAGE: int = 5
const FAMILIAR_RANGE_PX: float = 320.0

## Blot Bomb
const BOMB_COOLDOWN_SECONDS: float = 7.0
const BOMB_THROW_MAX_PX: float = 240.0
const BOMB_FLIGHT_SECONDS: float = 0.4
const BOMB_RADIUS_PX: float = 90.0
const BOMB_DAMAGE: int = 35

## Attack changes
const SPLIT_SHOTS: int = 3
const SPLIT_SPREAD_DEG: float = 12.0
const SPLIT_DAMAGE_SCALE: float = 0.5
const PIERCE_COUNT: int = 2
const HOMING_TURN_RAD_PER_S: float = 5.0
const HOMING_RANGE_PX: float = 260.0
const RICOCHET_BOUNCES: int = 2
const BURN_TICK_DAMAGE: int = 3
const BURN_TICK_SECONDS: float = 0.5
const BURN_TICKS: int = 4
const CHAIN_RANGE_PX: float = 140.0
const CHAIN_DAMAGE_SCALE: float = 0.5
const RAPID_FIRE_SCALE: float = 1.35
const HEAVY_DAMAGE_SCALE: float = 1.5
const HEAVY_FIRE_SCALE: float = 0.8
const HEAVY_KNOCKBACK_PX: float = 10.0

## Drops
const ROOM_CLEAR_CHOICES: int = 2              # walk over one, the other fades
const ELITE_DROP_CHANCE: float = 0.30
const STANDARD_HEART_CHANCE: float = 0.05


static func exists(id: String) -> bool:
	return ALL.has(id)


static func info(id: String) -> Dictionary:
	return ALL.get(id, {})


static func display_name(id: String) -> String:
	return str(info(id).get("name", id))


static func kind(id: String) -> Kind:
	return info(id).get("kind", Kind.ATTACK)


static func icon(id: String) -> Texture2D:
	var path := ICON_DIR + id + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


static func hud_icon(id: String) -> Texture2D:
	var path := ICON_DIR + id + "_hud.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## The colour that says what kind of item this is (the medallion's rim).
static func kind_colour(id: String) -> Color:
	match kind(id):
		Kind.LIFE:
			return Palette.EMBER
		Kind.CONSUMABLE:
			return Palette.BLOOD_RUST
		Kind.ABILITY:
			return Palette.GILT
		_:
			return Palette.NIB_TEAL


## `count` different equipment ids, weighted, skipping unique items already
## owned and lives the player cannot hold any more of.
static func draw(count: int, owned: Array, lives: int) -> Array[String]:
	var pool: Array[String] = []
	var weights: Array[float] = []
	for id in ALL.keys():
		var e: Dictionary = ALL[id]
		if int(e["weight"]) <= 0:
			continue
		if e["unique"] and id in owned:
			continue
		if e["kind"] == Kind.LIFE and lives >= MAX_EXTRA_LIVES:
			continue
		pool.append(id)
		weights.append(float(e["weight"]))
	var out: Array[String] = []
	while out.size() < count and not pool.is_empty():
		var total := 0.0
		for w in weights:
			total += w
		var roll := randf() * total
		var pick := pool.size() - 1
		for i in pool.size():
			roll -= weights[i]
			if roll <= 0.0:
				pick = i
				break
		out.append(pool[pick])
		pool.remove_at(pick)
		weights.remove_at(pick)
	return out
