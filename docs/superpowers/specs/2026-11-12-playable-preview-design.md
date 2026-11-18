# Playable preview on the reference art — design

Branch `base-game`. Goal: open the project and watch the Nib Knight and the
bestiary move, shoot and die on the painted room, looking like the reference
images. Every mechanic gets a simple working version marked `PREVIEW` so its
GDD owner can replace it later.

## Decisions already made

- **Characters are the reference paintings, cut out.** The Blender renders
  stay in the repo and the pipeline is untouched; a new script makes a second
  sprite set from `docs/reference/`. One side view per creature, flipped
  horizontally for left-facing. The 8-direction turnaround is dropped for now.
- **All stubs get a working PREVIEW fill.** Movement, aim, shoot, HP, enemy
  chase/range/shoot, bullets hitting, grazing, Shockwave effects, kill energy,
  barrel and trap damage, waves, door unlock, room advance. Each fill is a few
  lines under a `# PREVIEW(<owner>):` comment; the GDD constants above them
  are the balance and are not changed.

## Art

### `pipeline/cutout_refs.py` → `assets/sprites/refs/`

| Source | Background | Output | Height |
|---|---|---|---|
| hero-nib-knight.png | checkerboard | `hero.png` | 84 px |
| enemy-armored-snail.jpg | checkerboard | `snail.png` | 60 px |
| enemy-hare-archer.jpg | parchment | `hare.png` | 88 px |
| enemy-rat-demon.jpg | checkerboard | `grotesque.png` | 100 px |
| boss-ink-scribe.png | flat dark | `scribe.png` | 190 px |
| props-sheet.png (8 cells) | flat dark | `lamp_oil.png`, `tome_1..3.png`, `trap_1..3.png`, `shell.png` | 44–56 px |

Keying: flood-fill from the image border through pixels within a colour
tolerance of the sampled background (both checker greys, or the parchment
range, or the dark flat). The ink outline on every painting stops the fill,
so interior greys and beiges survive. Then a 1 px erode and a 1.5 px feather
on the alpha so edges don't crawl. Downscale with Lanczos. Heights are bigger
than the 64 px anchor rule on purpose: these are painted, not pixel, and at
64 px the hare's bow and the knight's nib vanish. Hitbox radii in the scenes
do not change — the GDD's 8 px player hitbox is a gameplay number.

### Room

`room-painted-interior.png` becomes `room_02.png` at 1152 × 640 and the
default layout. Its floor is a trapezoid, so `layouts.json` gains an optional
per-room `floor_polygon`, `doors`, `spawn_markers` and `object_markers`
override; `RoomManager.load_layout` applies them to `Bounds`, the door
anchors and the markers when present. Rooms without overrides keep the shared
framing, so `room_01` and future rectangular rooms are unaffected.

### Presence

- Soft elliptical shadow under every character and prop (one generated
  gradient texture, scaled per sprite).
- Idle breathing (scale-y ±2 %), a walk bob while moving, a squash on firing,
  a flash on hit (already built). No particles beyond what exists.
- Facing: `_apply_facing` keeps the 8 names for owners, but with the ref set
  it only toggles `flip_h` for W / NW / SW.

## Mechanics (PREVIEW fills)

| Script | Fill |
|---|---|
| `Player.gd` | WASD → velocity × 220, `move_and_slide`; aim at mouse; hold shoot → `PlayerBullet` every 1/6 s from `Muzzle`; HP maths; `died`. |
| `PlayerBullet.gd` (new) | Flies at 520 px/s, 10 × multiplier damage to `Enemy`, `take_hit` on `EnvObject`, frees after 1.5 s. |
| `EnemyBullet.gd` | Hit → `take_damage(10)`, free; frees after 4 s. |
| `Enemy.gd` | Species speeds: snail 55, hare 95, grotesque 120, scribe 40. Melee species chase and deal 10 on contact (1 s cooldown). Ranged hold the GDD band and fire every 1.4 s; scribe fires a 12-bullet ring every 2.5 s plus an aimed 3-shot. Light separation between enemies. HP maths, `die()`. Hazard avoidance stays TODO (Dec 2 scope). |
| `GrazeMeter.gd` | `GrazeArea.area_entered` → `register_graze` if the bullet hasn't hit. |
| `Shockwave.gd` | Inside 150 px: free enemy bullets, 30 damage + 50 px knockback to enemies, `detonate()` barrels. |
| `CombatRewards.gd` | `register_kill` adds energy to the player's meter. |
| `EnvObject.gd` | Barrel: 30 damage in 96 px to enemies and player, chain other barrels. Trap: 15 damage to the body on it. |
| `RoomManager.gd` | `start_room` locks, places 1–3 objects, starts wave 0 after 0.8 s. Waves spawn the GDD composition at markers ≥ 200 px from the player (standard = snail/hare, elite = grotesque, boss = scribe). Last enemy down → next wave after 1.5 s or `room_cleared` + unlock. |
| `GameManager.gd` | After clear, the player walking within 40 px of a door anchor advances the room and respawns them at the opposite door. |
| `Player.tscn` | Gains the `Camera` node GameManager already references (disabled; the room is the viewport). |

## Testing

- `python3 pipeline/check_gdscript.py` before every Godot run.
- Godot 4.7.2 (Windows, via `cmd.exe`) on a mirror of the repo under
  `C:\Users\jlion\AppData\Local\Temp\p5`: `--headless --quit-after 120` must
  print no script errors.
- `tests/Screenshot.tscn` instances `Main`, drives a scripted player for a
  few seconds (spawn a wave, fire), saves PNGs, quits. Run windowed through
  the same mirror; the PNGs are the visual check against the refs.

## Out of scope

Boss arena room, 8-direction ref art, hazard avoidance, audio, menus, the
remaining nine room paintings.
