# Project 5

A top-down roguelite bullet-hell in Godot 4. Fight through 8 locked rooms,
graze enemy bullets to charge a Shockwave, beat the boss in room 8.

**Team:** K'von Gates · Daryl Watkins-Mattocks · Jarman
**Design:** [`GDD.pdf`](GDD.pdf) — the source of truth for every number here.

---

## Status

The **visual layer is built**; the mechanics are not. Every mechanic from the
GDD exists as a documented stub for its owner to fill in.

Start here: **[`docs/VISUAL_SCAFFOLD.md`](docs/VISUAL_SCAFFOLD.md)** — who owns
what, how to read a stub, and the decisions made along the way.

---

## Running it

Open `project.godot` in **Godot 4.4 or newer**. `scenes/Main.tscn` is the main
scene.

You'll get a room with walls, locked doors, a HUD and a player sprite that
faces your mouse. Nothing moves yet — movement is a mechanic.

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
