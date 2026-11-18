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
# Measured from docs/reference by pipeline/extract_palette.py, and kept in
# step with PALETTE_HEX in pipeline/rig_common.py. If you change one, change
# the other.

# SIGNAL - gameplay colours. These came through the art-direction change
# unaltered, because the references already agreed with the GDD: the hero's
# nib glows teal, the boss fires magenta, his plume is ember.
const NIB_TEAL        := Color("35D6C4") ## Player shots, nib glow, power-up
const HOSTILE_MAGENTA := Color("FF2E6E") ## Enemy bullets ONLY
const EMBER           := Color("F06A2A") ## Hero plume, candle flame, barrels
const GRAZE_GOLD      := Color("FFC93C") ## Graze Meter, sparks, Shockwave ring

# WORLD - the scriptorium. Lighter and warmer than the GDD's original
# Crypt Stone / Stone Light, which were written before the references.
const PARCHMENT    := Color("E2C5A8") ## Paper, cape, gilt, UI text
const CANDLE_WARM  := Color("BE9E91") ## Stone near a candle
const STONE_LIT    := Color("8A8088") ## Floor in light - the main value
const STONE_MID    := Color("776B70") ## Wall faces
const STONE_SHADOW := Color("554F59") ## Wall shadow, floor out of the light
const INK_VIOLET   := Color("3C2C39") ## Deep shadow, recesses
const INK_BLACK    := Color("18030A") ## Ink pools, contour lines, the void
const GILT         := Color("C8A24E") ## Gold vine work on walls

# CREATURE + HERO
const CREATURE_VIOLET := Color("886181") ## Enemy flesh, fur, slug bodies
const CREATURE_RUST   := Color("BA7977") ## Enemy hide, shells, cloth
const DEEP_PLUM       := Color("421C39") ## Enemy shadow side
const STEEL           := Color("868178") ## Hero armour
const BLOOD_RUST      := Color("8E2A2A") ## Traps, damage flashes

# --- Role aliases ---------------------------------------------------------
# Prefer these over raw swatch names. If the art direction shifts again, the
# swatch a role points at changes here and nowhere else.

const BACKGROUND     := INK_BLACK
const INK            := INK_BLACK
const FLOOR          := STONE_LIT
const WALL           := STONE_MID
const COVER          := STONE_MID
const UI_TEXT        := PARCHMENT
const UI_HIGHLIGHT   := PARCHMENT
const BONE           := PARCHMENT      ## legacy GDD name
const SPIRIT_TEAL    := NIB_TEAL       ## legacy GDD name
const PLAYER_ACCENT  := EMBER
const BARREL         := EMBER
const FIRE           := EMBER
const TRAP           := BLOOD_RUST
const DAMAGE_FLASH   := BLOOD_RUST
const METER_FILL     := GRAZE_GOLD
const GRAZE_SPARK    := GRAZE_GOLD
const SHOCKWAVE_RING := GRAZE_GOLD
const PLAYER_SHOT    := NIB_TEAL
const POWER_UP       := NIB_TEAL
const ENEMY_BULLET   := HOSTILE_MAGENTA

## Every swatch by name, for tooling and the palette check.
const ALL := {
	"Nib Teal": NIB_TEAL,
	"Hostile Magenta": HOSTILE_MAGENTA,
	"Ember": EMBER,
	"Graze Gold": GRAZE_GOLD,
	"Parchment": PARCHMENT,
	"Candle Warm": CANDLE_WARM,
	"Stone Lit": STONE_LIT,
	"Stone Mid": STONE_MID,
	"Stone Shadow": STONE_SHADOW,
	"Ink Violet": INK_VIOLET,
	"Ink Black": INK_BLACK,
	"Gilt": GILT,
	"Creature Violet": CREATURE_VIOLET,
	"Creature Rust": CREATURE_RUST,
	"Deep Plum": DEEP_PLUM,
	"Steel": STEEL,
	"Blood Rust": BLOOD_RUST,
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
