# Room brief — producing the 10 layouts

The GDD needs **10 hand-built room layouts**. One (`room_01`) is a Blender
stand-in so the game runs. The other nine should be real painted art, because
a room is a single image with no rotation — exactly what 2D generation and
hand-painting are good at, and exactly where the Blender pipeline falls short.

This document is the contract. **Hit the framing below and a new room needs no
engine work at all** — drop the PNG in, add one line to `layouts.json`, done.
Miss the framing and someone has to author a collision polygon by hand.

---

> **12 Nov:** a room that cannot hit this framing (the two painted
> references don't) may list its own `floor_polygon`, `doors`,
> `spawn_markers` and `object_markers` in `layouts.json`; see `room_02` and
> `room_03` there. Hitting the framing is still the cheap path - it needs no
> coordinates at all.

## The framing (non-negotiable for rooms without overrides)

Every room image is the same canvas with the floor in the same place. That's
what lets all ten rooms share one collision polygon.

```
canvas            1152 x 640 px
floor rectangle   x 130 … 1022     y 132 … 613      (892 x 482)
wall band (top)   y 0 … 132        full width
wall band (left)  x 0 … 130         walls LEAN OUTWARD
wall band (right) x 1022 … 1152
near edge         no wall — below y 613 is dark void
```

The side walls **lean outward**, so they read as broad trapezoids rather than
thin strips — that is what makes the room a diorama box opened toward the
viewer, like the reference. Leaning the walls rather than using a perspective
camera keeps the floor a perfect rectangle, which is what lets an
orthographic sprite move across it without drifting out of alignment.

```
 0                                                            1152
 0 ┌──────────────────────────────────────────────────────────┐
   │  BACK WALL — dense gilt vine, 2 arched doors @ x~440,710  │
132├────┬───────────────────────────────────────────────┬──────┤
   │ \  │                                               │  /   │
   │  L │                                               │ R    │
   │  W │            F L O O R                          │ W    │
373│  A │← W door   keep this quiet — bullets fly here   │ A →E │
   │  L │                                               │ L    │
   │  L │                                               │ L    │
613├────┴───────────────────────────────────────────────┴──────┤
640│                     dark void                             │
   └──────────────────────────────────────────────────────────┘
    130                                                   1022
```

**Door anchors** (centre of each doorway, on the floor boundary):

| Door | Position |
|---|---|
| Back wall (two) | `(~440, 132)` and `(~710, 132)` |
| West | `(130, 373)` |
| East | `(1022, 373)` |

There is deliberately **no south door and no south wall** — the camera looks
into the room from that side. Your painted reference is composed exactly this
way.

**Wall height is a budget, not a free choice.** In a fixed 640 px canvas the
wall band and the floor share the vertical space, so taller, more ornate walls
directly cost play area. At one point the walls grew to 6 m and the floor fell
to 438 px, where the Shockwave's 150 px radius covered 69% of the room — close
to a free room clear. The shipped balance is a 132 px wall band and a 482 px
floor, where Shockwave covers 62%. If you make the walls grander, check that
number.

---

## Camera and perspective

- **Fixed 3/4 top-down, 45° elevation.** Same as every character and prop, so
  a sprite standing in the room belongs to the same picture.
- **Orthographic, not perspective.** Walls do not converge. The reference
  image converges slightly; don't copy that — a sprite moving across a
  converging floor drifts out of alignment.
- Three walls visible: top, left, right. Each wall is a shallow band, not a
  tall backdrop.

---

## What goes where

**On the walls — this is where ornament belongs.** Gilt vine filigree, arched
doorways with timber doors, pilasters at the corners, wall sconces, candles
with running wax. Nothing is dodged up here, so detail is free.

**On the floor — keep it quiet.** Plain stone with a low-contrast circular
rune inlay near the centre, and that's close to it. Note the reference floor
has **no visible flagstone joints at all** — a bold seam grid is the fastest
way to make a room look cheap. The GDD's avoid
list bans *"busy, high-contrast floor textures where bullets travel"*, and your
own arena reference obeys it: its mandala inlay is barely a value step above
the stone. All of the floor's interest comes from light and ink, not pattern.

**Storytelling props, flat on the floor:** spilled black ink pools, loose
manuscript pages, dropped quills, a fallen flower, wax spatter. These sit flat
and never stand tall enough to hide a bullet.

**Light:** warm candlelight from the top-left falling across cool grey-violet
stone, ideally with one visible shaft. That warm-on-cool contrast is the single
thing that makes the reference feel lit rather than flat. Key light direction
is fixed top-left across the whole project.

---

## Palette

Measured from the references by `pipeline/extract_palette.py`. Stay inside it.

| Role | Hex | Use |
|---|---|---|
| Stone Lit | `#8A8088` | Floor in light — the room's dominant value |
| Stone Mid | `#776B70` | Wall faces |
| Stone Shadow | `#554F59` | Wall shadow, floor away from the light |
| Candle Warm | `#BE9E91` | Stone near a flame |
| Parchment | `#E2C5A8` | Loose pages, highlights |
| Gilt | `#C8A24E` | The gold vine work |
| Ink Violet | `#3C2C39` | Deep shadow, recesses |
| Ink Black | `#18030A` | Ink pools, contour lines, the void |
| Ember | `#F06A2A` | Candle flame only |

**Forbidden on scenery, without exception:**

- **Magenta or pink (`#FF2E6E`)** — reserved for enemy bullets and nothing
  else. This is the hardest rule in the project: the core mechanic is grazing
  within 20 px of a bullet, and a pink prop makes that unreadable.
- **Teal (`#35D6C4`)** — the player's colour. Their shots, their nib, their
  power-up. A teal object in the scenery reads as a pickup.

---

## Prompt

Append this to any image-generation prompt, unchanged, so every room matches:

> *top-down 3/4 orthographic view of a gothic scriptorium chamber, hand-inked
> illustration with bold dark contour lines and flat painterly colour, ornate
> gilt vine filigree and arched timber doors on the stone walls, plain
> low-contrast grey-violet flagstone floor, spilled black ink pools and
> scattered manuscript pages on the ground, warm candlelight from the upper
> left across cool stone, limited palette of grey-violet stone, parchment
> cream, gold and ember orange, no magenta, no teal, no text, no watermark,
> clean readable composition, empty centre*

Then add the room's own line — see the ten below.

**Also say, every time:** three walls (top, left, right), no bottom wall, floor
running off the bottom edge, one arched door centred on each of the three
walls, nothing standing tall in the middle of the floor.

---

## The ten layouts

One per room. Rooms 1–6 are combat, 7 is the elite room, 8 is the boss arena;
the remaining two are spares so the pool exceeds the run length and the GDD's
"no repeats in a run" rule has room to work.

| # | Room | Added line for the prompt |
|---|---|---|
| 01 | **Scriptorium** | *rows of empty writing desks against the walls, a toppled inkwell* |
| 02 | **Stacks** | *towering bookshelves built into the walls, ladders, loose folios* |
| 03 | **Binding Room** | *presses and cutting tables along the walls, leather offcuts underfoot* |
| 04 | **Flooded Cellar** | *shallow black ink flooding the floor, stone steps, dripping arches* |
| 05 | **Candle Vault** | *hundreds of guttering candles in wall niches, heavy wax flows* |
| 06 | **Map Room** | *vast faded chart inlaid into the floor, brass instruments on the walls* |
| 07 | **Reliquary** (elite) | *gilded alcoves holding sealed tomes, heavier gold, colder light* |
| 08 | **The Scriptorium Throne** (boss) | *huge circular ink stain across the floor, a towering empty lectern, pages suspended mid-air* |
| 09 | Spare — **Drying Room** | *sheets of vellum hung on lines overhead, soft diffuse light* |
| 10 | Spare — **Ash Archive** | *burnt shelves, charred pages, embers in the corners* |

Room 8 should read as the arena from your reference: the biggest ink stain in
the game, because that ink is the boss.

---

## Recommended: repaint, don't generate from scratch

The Blender room (`room_01.png`) is a **composition lock**, not finished art.
It exists to pin the geometry; an image model supplies the painterly quality
that geometry cannot.

Image models do not hit exact pixel coordinates. If you ask for a room from
nothing, its floor will not land in the rectangle above, and every room will
then need its collision polygon authored by hand. Asking for a *repaint* of an
existing composition avoids that entirely — the framing survives, the existing
JSON still applies, and collision costs nothing.

**The workflow:**

1. Give the model two images: `assets/sprites/rooms/room_01.png` as the
   **composition and perspective reference**, and
   `docs/reference/room-painted-interior.png` as the **style reference**.
2. Use the prompt below.
3. Save the result as `room_NN.png` at exactly 1152 × 640.
4. Add the line to `layouts.json` and run `make_scenes.py`.

**Repaint prompt:**

> *Repaint this room in the style of the second image: hand-inked
> illustration, bold dark contour lines, flat painterly colour, visible paper
> grain. **Keep the composition, perspective, wall angles, door positions and
> floor boundary exactly as they are in the first image.** Add dense ornate
> gilt vine filigree across the wall faces, warm candlelight pooling on cool
> grey-violet stone, and keep the floor plain and low-contrast. No magenta, no
> teal, no text, no watermark.*

The emphasised sentence is the one that matters. Without it the model will
recompose the room and the collision polygon stops matching the art.

**Check before accepting a room:** the floor corners must still sit at
`(130, 132)`, `(1022, 132)`, `(1022, 613)`, `(130, 613)`. If the repaint has
drifted, either regenerate or give that room its own `room_NN.json`.

---

## Adding a finished room

1. Export at **1152 × 640**, PNG, with the floor exactly in the rectangle above.
2. Save it as `assets/sprites/rooms/room_NN.png`.
3. Add a line to `assets/sprites/rooms/layouts.json`:

```json
{ "name": "room_02", "image": "room_02.png", "source": "painted" }
```

4. Run `python3 pipeline/make_scenes.py`.

That's it. Collision, doors, spawn points and object markers all come from the
shared `framing` block, because the room conforms to it.

**If a room can't hit the framing** — a different floor shape, say — it needs
its own `room_NN.json` with a `floor_polygon`, in the same format
`pipeline/room.py` writes. Prefer conforming; it's free.
