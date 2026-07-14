# Battle Command UI — Concept V1

Status: the approved icon frames and icon family are wired into `BattleScene.gd`.
The current battle-menu layout, sizing, navigation, labels, descriptions and
animations remain unchanged; the Command Ribbon / Skill Drawer layout concept is
still deferred.

## Direction

The concept uses a restrained **Command Ribbon + Skill Drawer** system:

- Design space: `960 × 540`.
- Command ribbon: `470 px` wide, anchored in the current lower center-right menu zone.
- Eight command sockets remain a fixed `48–52 px`; they never shrink as entries are added.
- The player skill drawer opens upward as a `2 × 4` grid.
- Each skill tile is approximately `210 × 46 px` with a `38–40 px` icon.
- A companion with four skills uses the same parts as a `2 × 2` drawer.
- Item lists use the same tile family and cap at four visible rows before scrolling.
- Selection uses a broken antique-gold bracket, one sapphire jewel, a subtle underlight, and a `3 px` lift.
- Disabled skills are desaturated and use empty red SP pips without a large lock overlay.

The component construction is modular: fixed left/right caps, repeatable center rails/fills, separate corners and state overlays. Decorative motifs are never stretched.

## Palette

- Near-black royal navy: `#0A0E1B`
- Deep navy: `#06080F`
- Antique gold: `#C99A45`
- Warm ivory: `#EDE3C7`
- Sapphire selection: `#38BDF2`
- Insufficient SP: `#A9212B`

## Deliverables

- `mockup_skill_drawer_v1.png` — integrated battle mockup, player skill state.
- `mockup_command_ribbon_v1.png` — integrated battle mockup, closed main-command state.
- `component_sheet_v1.png` — modular command, skill-tile, drawer, and micro-control parts.
- `command_player_icon_atlas_v1.png` — command icons, Back, and all eight player skills.
- `companion_icon_atlas_a_v1.png` — first twelve companion skills.
- `companion_icon_atlas_b_v1.png` — remaining eleven companion skills.

All source sheets were generated through the project's `OpenAiExtension` bridge.
Their green backgrounds remain as reproducible cutting fields; the production
build script performs border-connected chroma cleanup and per-icon alpha export.

Production assets are generated from these sheets by:

```bash
python3 tools/build_battle_command_v1_assets.py
```

The script writes two aligned transparent frame states to
`assets/ui/battle_command_v1/components/` and all 40 transparent icon textures to
`assets/ui/battle_command_v1/icons/`.

## Atlas mapping

### Command + player atlas (`4 × 5`, row-major)

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | Attack | Skill | Probe | Item |
| 2 | Guard | Flee | Finisher | Spare |
| 3 | Back | Strike | Power Strike | Focus |
| 4 | Ember Slash | Crush | Mend | Tempest |
| 5 | Pierce | Empty | Empty | Empty |

### Companion atlas A (`4 × 3`, row-major)

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | Venom Fang | Flame Burst | Frost Lance | Thunder Jolt |
| 2 | Shadow Drain | Wild Flurry | Skull Crack | Armor Break |
| 3 | Lullaby | Blinding Dust | Silencing Seal | Slow Mire |

### Companion atlas B (`4 × 3`, row-major)

| Row | Column 1 | Column 2 | Column 3 | Column 4 |
| --- | --- | --- | --- | --- |
| 1 | War Cry | Stone Ward | Quicksilver | Purify |
| 2 | Soothing Light | Verdant Rain | Regrowth | Guiding Star |
| 3 | Taunt | Iron Bastion | Shield Bash | Empty |

## Typography

- Selected title / actor-facing display text: Playfair Display family.
- Functional text, descriptions, cost, quantity: Be Vietnam Pro family.
- Runtime text remains separate from textures for localization and sharp scaling.
