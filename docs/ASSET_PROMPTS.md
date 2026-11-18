# Asset generation prompts

Ready-to-paste prompts for producing the final painted art with an
image-generation model (the references themselves are Gemini output, so that
is the natural choice — attach the reference images listed with each prompt).

The engine side is already built to receive this art:

- **Rooms** → follow the repaint workflow in [`ROOM_BRIEF.md`](ROOM_BRIEF.md).
  Do not generate rooms from scratch; repaint `room_01.png` so the collision
  framing survives.
- **Props** → prompts below, then run the import tool to size them:

```bash
blender -b --python pipeline/import_asset.py -- \
    --src ~/Downloads/generated_barrel.png \
    --out assets/sprites/props/barrel.png \
    --frame 80 --content-height 40
```

The import tool crops to the art's transparent-background bounding box,
scales it so the content lands at the right pixel size next to the 64 px
hero, and centres it in the frame the scenes already reference. **Generate
with a transparent background** (or remove it first) — the tool keys on
alpha.

---

## Style suffix

Append to every prop prompt, unchanged:

> *hand-inked game sprite, bold dark contour lines, flat painterly colour
> with brushstroke highlights, strong top-left key light and warm rim light,
> dark gothic scriptorium mood, limited palette of grey-violet, parchment
> cream, ember orange and gold, clean readable silhouette, 3/4 top-down view,
> isolated on a transparent background, no text, no watermark*

Attach `docs/reference/props-sheet.png` as the style reference every time, so
the whole set comes out matching.

**Never in any prop:** magenta/pink (enemy bullets only) or teal (the
player's colour — the Pigment Shell is the single exception, because it IS a
player pickup).

---

## The props

Target sizes are what the committed scenes expect. "Content" is the art
itself; the frame is the transparent canvas the import tool centres it in.

| Prop | File | Frame | Content height |
|---|---|---|---|
| Explosive Lamp Oil | `barrel.png` | 80 | ~40 px |
| Tome Stack ×3 | `cover_intact/cracked/crumbling.png` | 112 | ~56 px |
| Scribe's Trap ×3 | `trap_disarmed/armed/triggered.png` | 96 | ~60 px |
| Pigment Shell | `powerup_shell.png` | 64 | ~26 px |

**Explosive Lamp Oil** (the barrel — 2 hits, 30 dmg in 96 px)
> A round glass flask full of glowing burning orange lamp oil, slung in a
> knotted rope net, a lit wick and small flame at its neck, embers rising,
> sitting on the ground. + suffix

**Defensive Tome Stack** (cover — 3 damage stages; generate all three so they
read as the same stack decaying)
> 1. A neat stack of four thick leather-bound tomes with riveted metal corner
>    plates, bound shut by a leather strap and an iron padlock. + suffix
> 2. The same stack of tomes knocked out of line, the padlock broken on the
>    ground, loose manuscript pages spilling from the books. + suffix
> 3. The same stack collapsing, covers torn, the top book slid off, loose
>    pages scattered all around it. + suffix

**Scribe's Trap** (15 dmg, re-arms in 2 s — 3 states)
> 1. A flat square rusted-iron floor plate with a grid of empty dark sockets,
>    corner bolts, lying flush with the ground. + suffix
> 2. The same plate with a grid of upturned steel pen nibs standing like
>    spikes, each nib with a visible slit. + suffix
> 3. The same plate just triggered, the pen-nib spikes wet with violet ink,
>    small ink droplets flung in the air. + suffix

**Luminous Pigment Shell** (the every-5th-kill power-up)
> A small spiral snail shell lying in dark leaf litter, its mouth overflowing
> with glowing teal pigment, wisps of teal vapour rising from it. + suffix

---

## What NOT to generate

- **Bullets.** They stay procedural. A bullet must be an exact flat-colour
  disc whose nose sits precisely on its hitbox — the 20 px graze window is
  measured from it, and painted ambiguity there breaks the core mechanic.
- **Characters.** The hero and creatures need 8 consistent facing directions
  of the same model, which image generation does not do reliably. They stay
  in the Blender pipeline.

## After importing anything

```bash
python3 pipeline/check_anchor.py assets/sprites/props/<file>.png
```

Confirm the content size and that the palette report shows no magenta and no
teal (Pigment Shell excepted).
