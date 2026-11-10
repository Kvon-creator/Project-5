extends Node
## The GDD palette, as code. Autoloaded as `Palette`.
##
## One rule above the rest, straight from the GDD:
##     Hostile Magenta appears on enemy bullets and nothing else, so bullets
##     always read against the room.
##
## Use `Palette.ENEMY_BULLET` for enemy bullets and never reach for MAGENTA
## anywhere else. `Palette.check_no_magenta()` enforces it at runtime in debug
## builds, so a stray pink tint gets caught the first time the scene loads
## rather than in playtesting.

# --- Swatches -------------------------------------------------------------
# Name, hex and "used for" are copied verbatim from the GDD Palette table.

const ABYSS          := Color("120E1A")  ## Void, background, ink outlines
const CRYPT_STONE    := Color("2B2335")  ## Floor tiles
const STONE_LIGHT    := Color("4E4458")  ## Walls, destructible cover
const BONE           := Color("D8C8A8")  ## UI text, highlights
const EMBER          := Color("F06A2A")  ## Player accents, barrels, fire
const BLOOD_RUST     := Color("8E2A2A")  ## Traps, damage flashes
const GRAZE_GOLD     := Color("FFC93C")  ## Graze Meter, sparks, Shockwave ring
const SPIRIT_TEAL    := Color("35D6C4")  ## Player shots, damage power-up
const HOSTILE_MAGENTA := Color("FF2E6E") ## Enemy bullets ONLY

# --- Role aliases ---------------------------------------------------------
# Prefer these over the raw swatch names. If the art direction shifts, the
# swatch a role points at changes here and nowhere else.

const BACKGROUND     := ABYSS
const INK            := ABYSS
const FLOOR          := CRYPT_STONE
const WALL           := STONE_LIGHT
const COVER          := STONE_LIGHT
const UI_TEXT        := BONE
const UI_HIGHLIGHT   := BONE
const PLAYER_ACCENT  := EMBER
const BARREL         := EMBER
const FIRE           := EMBER
const TRAP           := BLOOD_RUST
const DAMAGE_FLASH   := BLOOD_RUST
const METER_FILL     := GRAZE_GOLD
const GRAZE_SPARK    := GRAZE_GOLD
const SHOCKWAVE_RING := GRAZE_GOLD
const PLAYER_SHOT    := SPIRIT_TEAL
const POWER_UP       := SPIRIT_TEAL
const ENEMY_BULLET   := HOSTILE_MAGENTA

## Every swatch by name, for tooling and the palette check.
const ALL := {
	"Abyss": ABYSS,
	"Crypt Stone": CRYPT_STONE,
	"Stone Light": STONE_LIGHT,
	"Bone": BONE,
	"Ember": EMBER,
	"Blood Rust": BLOOD_RUST,
	"Graze Gold": GRAZE_GOLD,
	"Spirit Teal": SPIRIT_TEAL,
	"Hostile Magenta": HOSTILE_MAGENTA,
}


## Nearest GDD swatch to an arbitrary colour, as [name, distance].
## Distance is in 0..1 RGB units; anything under ~0.08 is "on palette".
func nearest(c: Color) -> Array:
	var best_name := ""
	var best_dist := INF
	for swatch_name in ALL:
		var s: Color = ALL[swatch_name]
		var d := sqrt(pow(c.r - s.r, 2.0) + pow(c.g - s.g, 2.0)
				+ pow(c.b - s.b, 2.0))
		if d < best_dist:
			best_dist = d
			best_name = swatch_name
	return [best_name, best_dist]


## True if `c` reads as magenta/pink. Used by the guard below.
func is_magenta_ish(c: Color) -> bool:
	# Pink/magenta means red and blue both high, green clearly lower.
	return c.r > 0.5 and c.b > 0.25 and c.g < minf(c.r, c.b) * 0.75


## Walk a subtree and push a warning for any magenta-ish modulate on a node
## that is not an enemy bullet. Call from `_ready()` on room and player scenes.
##
## Catches the GDD's single hardest art rule the moment a scene opens, instead
## of during a playtest when a pink prop makes bullets unreadable.
func check_no_magenta(root: Node, _depth: int = 0) -> void:
	if not OS.is_debug_build():
		return
	for child in root.get_children():
		if child is CanvasItem and not child.is_in_group("enemy_bullet"):
			var ci := child as CanvasItem
			if is_magenta_ish(ci.modulate) and ci.modulate.a > 0.01:
				push_warning(
					"Palette rule broken: %s is magenta-ish (%s). " % [
						ci.get_path(), ci.modulate.to_html(false)
					]
					+ "Hostile Magenta is for enemy bullets only."
				)
		check_no_magenta(child, _depth + 1)
