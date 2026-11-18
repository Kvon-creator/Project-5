# Project 5

A top-down roguelite bullet-hell in Godot 4. Fight through 8 locked rooms,
graze enemy bullets to charge a Shockwave, beat the boss in room 8.

**Team:** K'von Gates · Daryl Watkins-Mattocks · Jarman
**Design:** [`GDD.pdf`](GDD.pdf) — the source of truth for every number here.

---

## Status

**Playable, every GDD mechanic in** (branch `kvon-mechanics`, 13 Nov, cut
from `backup-game`). Open it and you can walk, aim, shoot, graze, fire the
Shockwave, clear waves, walk through a door and reach the boss.
K'von's two mechanics (Environmental Combat, Room-Based Combat) and Jarman's
two (Combat Rewards, Enemy Adaptation) are implemented to the GDD. Daryl's two
have a simple working version marked `# PREVIEW(Daryl)` in their scripts;
those are placeholders for the owner to replace, not the final design. The
GDD constants above them are untouched. All ten layouts are in (seven are graded, mirrored and
fixture-shaped variants of the two painted references), and the boss has
three phases.

The characters and props are the **reference paintings themselves**, cut
out and scaled by `pipeline/cutout_refs.py`; two of the rooms are the
painted references. The Blender pipeline and its 8-direction renders are
still in the repo, one switch away (`SPRITE_SET` in `pipeline/make_scenes.py`).

Start here: **[`docs/VISUAL_SCAFFOLD.md`](docs/VISUAL_SCAFFOLD.md)** — who owns
what, how to read a stub, and the decisions made along the way.

---

## Running it

Open `project.godot` in **Godot 4.4 or newer** (tested on 4.7.2).
`scenes/Main.tscn` is the main scene.

WASD to move, mouse to aim, hold left-click to fire, Q for the Shockwave
once the graze meter is full. Clear the waves, walk up to a door, repeat;
room 7 is the Elite Court, room 8 is the Ink Scribe. SPACE dashes and E
throws a bomb once you have found those abilities.

**Items** *(not in the GDD; every number in `scripts/Items.gd` is proposed)*.
Each cleared room offers two items; walk over one and the other crumbles.
Elites drop one 30% of the time, and standard enemies drop a heart 5% of
the time while you are hurt. The GDD's damage shell every 5th kill is
unchanged and comes on top.

| Item | Kind | Effect |
|---|---|---|
| Phoenix Seal | life | +1 life (max 3): falling revives you at 50 HP, clears nearby shots |
| Heart of Ink | heal | +25 HP |
| Shadow Step | ability | SPACE: 150 px dash, untouchable mid-step, 0.9 s cooldown |
| Blot Bomb | ability | E: ink bomb at the cursor, 35 damage in 90 px, sets off barrels, 7 s cooldown |
| Warding Pages | ability | two orbiting pages eat enemy shots, then rest 1.2 s |
| Inkling | ability | an imp familiar that shoots the nearest foe (5 damage) |
| Split Nib | attack | three shots in a 24 degree fan, 5 damage each |
| Bodkin Nib | attack | shots pierce two foes |
| Seeking Ink | attack | shots home in |
| Mirror Ink | attack | shots bounce off walls twice |
| Ember Ink | attack | hits burn for 4 x 3 damage |
| Storm Quill | attack | hits arc to a foe within 140 px for half damage |
| Quickened Hand | attack | +35% fire rate |
| Leaden Nib | attack | +50% damage and knockback, -20% fire rate |

The mechanics come from the genre: Isaac's tear effects, Gungeon's dodge
roll and extra lives, Hades' chain lightning and dash. The icons are
game-icons.net glyphs (CC BY 3.0, see [`CREDITS.md`](CREDITS.md)), set
into painted medallions by `pipeline/item_icons.py`. The medallion's shape
tells you the kind of item: a round seal is a life or heal, a diamond is an
ability, a hexagon changes your shots.

**The boss.** 1,200 HP, three phases by health:

| Phase | HP | Patterns |
|---|---|---|
| I | 100-66% | slow rings of 12, aimed three-shot between them |
| II | 66-33% | + a two-armed ink spiral; opens by scribbling two hares into being, and again every 8 s (max 4) |
| III | 33-0% | rings of 16, aimed five-shot, faster spiral, and a lunge every 5 s (15 damage) |

Each phase change fires a ring, flashes the scribe, shakes the room, and
gives it 0.8 s of invulnerability. Its minions die with it.

Before pushing, run the checks that were run on every commit of this preview:

```bash
python3 pipeline/check_gdscript.py                 # static GDScript check
godot --headless --path . --quit-after 150         # must print no errors
godot --headless --path . res://tests/MechanicsTest.tscn   # GDD rule checks
godot --headless --path . res://tests/ItemsTest.tscn       # item checks
godot --path . res://tests/Screenshot.tscn         # saves build/shots/*.png
```

`MechanicsTest` plays a whole 8-room run and then sets up each barrel, cover
and trap case, printing PASS or FAIL per GDD rule for Environmental Combat
and Room-Based Combat; it exits non-zero if any rule fails.

The last one opens a window for a few seconds, drives the knight with fake
input, and saves frames you can hold up against `docs/reference/`.

## Playing it in a browser (GitHub Pages)

`docs/index.html` is a web build of the game. With GitHub Pages set to serve
the `/docs` folder of a branch (repo Settings -> Pages -> Deploy from a
branch), the game is playable at `https://kvon-creator.github.io/Project-5/`.

The build is a snapshot: rebuild it after changing the game, then commit the
`docs/index.*` files.

```bash
godot --headless --path . --export-release "Web" docs/index.html
```

That needs Godot's export templates installed and an `export_presets.cfg`
with a preset named `Web` (not in the repo, per `.gitignore`): threads off,
because GitHub Pages cannot send the headers a threaded build needs;
`*.json` in the include filter, because the room manifest is read as a plain
file; and `docs/*, build/*, pipeline/*, tests/*` excluded.

## Re-rendering the art

All art is generated from Blender scripts, so it can be re-rendered from
scratch and tweaked in version control rather than in a binary file.

```bash
./pipeline/render_all.sh          # render every asset  (~10 min)
python3 pipeline/check_anchor.py  # measure against the anchor asset
python3 pipeline/make_scenes.py   # regenerate scenes/*.tscn
```

Requires Blender 4.2+ (tested on 5.0.1). `check_anchor.py` and
`make_scenes.py` need only Python 3 — no packages.

## Layout

```
pipeline/   Blender render scripts + the scene generator
assets/     Rendered sprites and the TileSet  (generated)
scenes/     Godot scenes                      (generated)
scripts/    One script per GDD architecture box
docs/       Handoff notes
```
