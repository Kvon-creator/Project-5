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
room 7 is the Elite Court, room 8 is the Ink Scribe.

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
godot --path . res://tests/Screenshot.tscn         # saves build/shots/*.png
```

`MechanicsTest` plays a whole 8-room run and then sets up each barrel, cover
and trap case, printing PASS or FAIL per GDD rule for Environmental Combat
and Room-Based Combat; it exits non-zero if any rule fails.

The last one opens a window for a few seconds, drives the knight with fake
input, and saves frames you can hold up against `docs/reference/`.

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
