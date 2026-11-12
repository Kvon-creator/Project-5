# Project 5

A top-down roguelite bullet-hell in Godot 4. Fight through 8 locked rooms,
graze enemy bullets to charge a Shockwave, beat the boss in room 8.

**Team:** K'von Gates · Daryl Watkins-Mattocks · Jarman
**Design:** [`GDD.pdf`](GDD.pdf) — the source of truth for every number here.

---

## Status

**Playable preview** (branch `base-game`, 12 Nov). Open it and you can walk,
aim, shoot, graze, fire the Shockwave, clear waves, walk through a door and
reach the boss. Every mechanic from the GDD has a simple working version
marked `# PREVIEW(<owner>)` in its script; those are placeholders for the
owner to replace, not the final design. The GDD constants above them are
untouched.

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
room 8 is the boss.

Before pushing, run the checks that were run on every commit of this preview:

```bash
python3 pipeline/check_gdscript.py                 # static GDScript check
godot --headless --path . --quit-after 150         # must print no errors
godot --path . res://tests/Screenshot.tscn         # saves build/shots/*.png
```

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
