# Playtest weather sheets

The weather sheets are 18×8 atlases of 16-pixel cells used only by the
AW1/AW2 playtest renderer:

- `terrain_aw1_snow.png` for Advance Wars (AW1 has no rain weather)
- `terrain_aw2_rain.png` and `terrain_aw2_snow.png` for Advance Wars 2

They preserve the existing GBA terrain layout and apply the Rain/Snow palette
treatment shown by the Advance Wars 2 map tileset references on [The Spriters
Resource](https://www.spriters-resource.com/game_boy_advance/advancewars2blackholerising/).
The AW1 and AW2 files currently share the same underlying terrain pixels where
the GBA terrain geometry is shared, but remain separate resources so the two
cartridges can diverge without changing palette routing.

The underlying Advance Wars artwork remains copyright Nintendo and Intelligent
Systems. These files are compatibility artwork for this unofficial editor; the
project does not claim ownership of the game assets.

## Historical map-art sheets

- The `_6` sheets are source-derived repacks of the cleaned 111×192,
  16-pixel-grid Famicom Wars extraction supplied for this project. The
  matching original listing is [Famicom Wars (JPN) tileset on The Spriters
  Resource](https://www.spriters-resource.com/nes/famicomwarsjpn/asset/11797/).
  The source is not a simple editor-atlas grid: the 16×32 port/airport/city
  sprites occupy paired rows, while Famicom HQ and Base sprites are single
  16×16 cells. The repack keeps those coordinates explicit: `c6/r0–r5` are
  the neutral, Red Star, and Blue Moon city pairs; `c0/c2 r2–r3` and
  `c1/c3 r2–r3` are the faction port and airport pairs; `c0/c2 r6` are the
  Red Star/Blue Moon HQ cells; `c4/c5 r6` are the Red Star/Blue Moon Base
  cells, and `c5/r1` is the neutral Base cell used for the neutral row and as
  the additional-army recolor template. One-cell HQ/Base art is placed in the
  top row of each building group and rendered at 16 pixels, while the paired
  sprites retain their 32-pixel height.

  Famicom Wars exposes only its original Red Star and White Moon armies in
  the editor and playtest. Green Soil and Yellow Comet are fan additions and
  are intentionally not available for this tileset; Black Hole is likewise
  omitted because it is not a Famicom Wars army. Super Famicom Wars keeps its
  own four-army roster.

  The terrain atlas maps the named shoreline rows directly (the source rows
  containing `Land_Border_*`), with the twelve coast-overlay cells oriented to
  the renderer's left/right/up/down and diagonal land tests, followed by
  `River_NS`, road, and bridge rows.
  The generic Mountains button uses the source `Mountain_base` cell, while
  the remaining mountain pieces remain available in their adjacent terrain
  slots. The bridge button uses the `Bridge_WE` span, not one of its handle
  cells. Famicom Wars has no Advance Wars Ruins, pipe/seam, Missile Silo, Com
  Tower, or Lab content, so those editor-only palette entries are omitted and
  their atlas slots remain transparent. The canonical Reef and flat cyan
  Shoal preview cells are assigned to the matching Famicom visuals rather
  than inheriting the generic AWED order; Famicom Shoal stays on that single
  cell in every map position instead of using the later shoreline variants.
  The Famicom authoring palette also omits the
  Dual Strike-only Extra tab. The unit atlas uses the matching [Famicom Wars
  map-unit extraction](https://www.spriters-resource.com/nes/famicomwarsjpn/asset/215810/),
  fitted into AWED's 16-pixel unit cells. Only the original Red Star and White
  Moon faction rows are exposed for Famicom authoring; unsupported army rows
  are left as the plain ground plate rather than leaking later-game artwork,
  while neutral property rows remain neutral. Every opaque pixel in the unit
  and building sheets is
  normalized to a valid colour from the NTSC 2C02 PPU's 64-entry palette.
  Populated historical unit/property frames use the exact Famicom Plains green
  `(72,168,16)` as their ground plate. Every 16×16 Famicom unit cell also
  carries a one-pixel black rule along its final row and column. The river slots are hand-pixeled
  directional variants (straight, turns, tees, and cross), derived from the two
  source River_NS rhythms instead of repeating one vertical cell.
  The Famicom cursor atlas (`misc_6.png`) uses the same common NTSC 2C02
  display entries for its opaque pixels: `$0F` black `(0,0,0)`, `$30` white
  `(252,252,252)`, and `$3A` pale green `(184,248,184)`.
- The `_7` sheets use the supplied 16×16 Game Boy Wars tile references as a
  four-tone source. The Sea, Shoal, Plains, Road, Woods, Mountain, Bridge,
  and River cells in `terrain_7.png` are reduced from the corresponding
  `geo/01.gif`–`geo/08.gif` captures on the [GBW terrain guide](https://gbw.netgamers.jp/n/geo.html).
  GB Wars uses finished square cells for terrain, with distinct horizontal and
  vertical bridge cells. The map renderer preserves that bridge orientation
  while keeping road, river, shoreline, and mountain sprites flat rather than
  synthesizing Advance Wars variants. The atlas uses the GB four-tone ramp
  `(0, 26, 136, 255)` and leaves unsupported Ruins, Reef, Pipe, and Pipe Seam
  slots transparent.
  `unit_7.png` follows the existing `unit_6.png` silhouettes with strict
  black/white ordered dithering: rows 0–1 are black-dominant Red Star, and
  rows 2–3 are white-dominant White Moon with a one-pixel black silhouette
  outline for legibility. The other army rows remain transparent because GB
  Wars only exposes those two playable armies. GB property art is 16×16, but
  its faction rows are stored on a two-row cadence in `building_7.png`; the
  renderer maps those rows explicitly instead of treating the buildings as
  16×32. HQ and Factory use the two variants from `geo/09.gif` and `geo/10.gif`;
  Airport, Port, and City use Red Star, White Moon, and neutral variants from
  `geo/11.gif`–`geo/13.gif`, all reduced with nearest-neighbor sampling and
  quantized to the same ramp. There is no neutral HQ or Factory in the guide,
  so those synthetic cells are omitted from the GB palette. These are
  reference-derived GB Wars approximations, not a claim to be a canonical
  full ROM rip.

- `unit_6.png` is built from the Famicom Wars map-unit reference on [The
  Spriters Resource](https://www.spriters-resource.com/nes/famicomwarsjpn/asset/215810/),
  not from an Advance Wars recolor. The sixteen original map units are copied
  from their 16×16 Red Star and Blue Moon cells, with the source's plains-green
  plate and NES palette retained. The source's labels and attribution strip
  are excluded from the atlas. The Famicom unit palette exposes only those
  sixteen original unit types, using the shared slots for Howitzer, Supply
  Truck, Helicopter, and Scout where the cross-game element format has no
  separate identity.

The historical sheets intentionally replace the prior palette-recolor
fallback. They preserve the source silhouettes and layout selected from those
references while applying the source system's palette constraints and the
Famicom ground treatment; transparent extra-object cells indicate that the
original extract did not provide an equivalent AWED/DS extra-object table.

Every terrain artstyle uses compositable bridge alpha without sharing a bridge
silhouette. Existing source alpha is authoritative. When a source bridge is an
opaque rip, the assembler removes only its border-connected outer plate on the
sides perpendicular to its span, then preserves every original pixel inside the
detected bridge bounds. This keeps black outlines and uniform same-colour deck
fills intact. Live editing, playtest, selection previews, and screenshot exports
draw those overlays over the map's matching river orientation when a river
neighbour exists, otherwise over that artstyle's sea tile. Rebuilding historical
atlases reapplies this design-derived normalization, and `--bridges-only` can
normalize all bundled terrain sheets without rerunning ROM extraction.

Shore pieces and buildings follow the same compositing rule. Existing source
alpha remains authoritative. For an opaque source cell, the assembler removes
only its single dominant border-connected plate colour and restores every
original pixel inside the bounds established by the remaining artwork. This
keeps black outlines, windows, and same-colour interior fills intact. The map
renderer supplies each transparent property with its artstyle's plains tile,
or shoal beneath a port. `--overlays-only` reapplies the shore/building alpha
normalization without rebuilding the historical atlases.

## Additional Wars variants

The map-art picker also exposes the later historical variants in release
order: Super Famicom Wars (1998), Game Boy Wars 2 (1998), Game Boy Wars 3
(2001), and Advance Wars: Days of Ruin / Dark Conflict (2008). Their values
are persisted as distinct tilesets, so a map can retain the author's chosen
game identity instead of silently collapsing back to an Advance Wars name.

The public reference material for these cartridges is not equally complete, so
the normalized sheets make that distinction explicit instead of silently
aliasing every game to another game's art:

- `*_8` (Super Famicom Wars) uses the supplied
  `ROMs/superfamicomwars.sfc` for its native LZN-decoded static/icon/animated
  banks and all 24 map-unit streams. The raw 4bpp bank does not include the
  runtime metatile table or CGRAM palette, so the terrain/property assembler
  uses the translation project's genuine 32×32 in-game terrain-guide
  captures (`sfw-f01.gif` … `sfw-f16.gif`) to recover complete metatile
  boundaries and their displayed palette. Each complete map tile is reduced
  once to AWED's 16-pixel grid with nearest-neighbour sampling. Projecting
  city/airport frames use their actual `x=48+32n` centres. Ports use the full
  32×48 guide frame, normalized to a bottom-aligned 16×24 sprite in the tall
  property slot, instead of discarding their upper third with a 32×32 crop.
  Neutral Base and Port use the guide's genuine neutral images; neutral City
  and Airport come from the five-variant captures. SFW exposes only four HQ
  images, so the nonexistent neutral HQ slot remains transparent rather than
  being synthesized from an army colour. The SFW-only Research Laboratory and
  Train Station use their five genuine guide variants in the shared Lab and
  Com Tower columns respectively. SFW Railroad uses the shared Pipe topology
  slots, with native horizontal, vertical, and four corner metatiles from the
  ROM's static 4bpp terrain bank; the Pipe Seam slots remain empty because SFW
  has no equivalent terrain. The captures are extraction inputs only and are
  not bundled with the app.
- `*_10` (Game Boy Wars 2) is assembled directly from `ROMs/gbw2.gbc`:
  native 16×16 property groups and map-unit groups use the cartridge's CGB
  palettes, while map terrain uses the explicit four-quadrant metatile table
  at `$19000` (including its 34 coastline entries at `$19120..$191A4`). The
  four tile IDs in a map cell are not assumed to be consecutive: plains are
  `8A FF 90 91`, mountains are `9E 9F AE AF`, and bridge/river cells are
  oriented from their native vertical definitions. The interleaved property
  table is normalized as `HQ, City, Base, Airport, Port`: Red Star uses
  `C0, AA, A2, C8, CC`, White Moon uses `BC, A6, 9A, C4, E0`, and the neutral
  row uses only city `96`. The `D0`/`92` entries are the second port frames and
  are intentionally not exposed as static building cells. CGB colours stay on the hardware's
  5-bit-shifted steps, matching the supplied ROM sea reference exactly. A
  captured VRAM/palette dump remains an ignored fallback when the ROM is
  unavailable; no dump is bundled.
- `*_11` (Game Boy Wars 3) uses the native 2bpp unit artwork from the [GB Wars
  3 translation project](https://github.com/REONTeam/gbwars3-en) and crisp
  16×16 map properties reconstructed from the supplied high-resolution map
  references. The large public [Places sheet](https://www.spriters-resource.com/game_boy_gbc/gbwars3/asset/18437/)
  is event/presentation art, so it is deliberately excluded from the map
  atlas. Red Star and White Moon HQ, City, and Base icons remain one logical
  map cell and keep the atlas's two-row property cadence. Airport and Port
  retain the established GBW3 cells until a clean unoccluded map capture for
  those two properties is available.
  Airport and Port retain the established GBW3 cells until a clean unoccluded
  map capture for those two properties is available. The six supplied GBW3 map
  cells are used verbatim in the canonical terrain slots: Plains, Mountain,
  Sea, Road, Woods, and Bridge. The remaining edge/variant slots retain the
  four-tone GB reference until native GBW3 variants are available.
- `*_9` (Days of Ruin / Dark Conflict) uses `ROMs/awdor.nds` to unpack the
  map NARCs and decode their Nintendo DS `0x10` LZ77 `.tex` payloads to native
  512×512 linear-4bpp intermediates, retaining the game's `.cl` palettes. The
  labelled Normal-map and map-unit rips provide the explicit metatile/unit
  ordering needed to map those banks into AWED's different atlas contract.
  Normal-map properties are 16×24 (a 16×16 base plus two upper 8×8 tiles) and
  are bottom-aligned in AWED's 16×32 storage slot. Units come exclusively from
  the compact right-hand `Idle` table: one 16×16 frame per unit. The larger
  left-hand idle art and the entire movement-animation table are excluded.
  The game's four factions occupy the shared Orange Star, Blue Moon, Gold
  Comet, and Black Hole rows as 12th Battalion, Lazuria, New Rubinelle Army,
  and Intelligence Defense Systems. The unused Green Earth row stays
  transparent in both property and unit atlases. IDS uses its own near-black
  charcoal unit ramp and UI accent rather than the shared Black Hole purple.

These are source-derived compatibility sheets and the project makes no claim
of ownership. The variant cards and playtest header keep the selected game's
name visible, while playtest mechanics use the nearest implemented rule table
until a cartridge-specific table is added.

## Historical cursor sheets

The original wxAWDS editor stores cursor art in a fixed 80×128 `misc` atlas:
the 16×16 allowed and forbidden pointers, the 32×16 delete pointer, and the
18×18/48×48/64×64 map-frame slots are all consumed by `CursorAtlas.swift`.
`misc_0`, `misc_4`, and `misc_5` remain the original Dual Strike, Advance Wars,
and Advance Wars 2 sheets. The six additional sheets keep the binary layout
and nearest-neighbour pixel style, but follow the historical games' actual
map-cursor treatment: the allowed-arrow and forbidden-X slots are transparent
because those games show corner angles instead, and the delete slot carries a
compact wrench badge rather than the AWDS hammer:

| sheet | game | visual reference used |
| --- | --- | --- |
| `misc_6` | Famicom Wars | white/green four-corner map cursor visible in the Famicom gameplay capture on [Famitsu](https://www.famitsu.com/article/202408/12967) |
| `misc_7` | Game Boy Wars | DMG four-tone green ramp used by the original Game Boy map screenshots; the `E` badge is the game's used-unit marker, not cursor artwork |
| `misc_8` | Super Famicom Wars | red/salmon/white corner cursor visible in the [Super Famicom Wars map-unit reference](https://www.spriters-resource.com/snes/superfamicomwarsjpn/asset/125563/) and strategic-map capture |
| `misc_9` | Days of Ruin / Dark Conflict | charcoal, cream, and red DS map palette from the [Days of Ruin reference sheets](https://www.spriters-resource.com/ds_dsi/advwarsdor/); its crosshead cursor semantics are described in the [gameplay reference](https://strategywiki.org/wiki/Advance_Wars:_Days_of_Ruin/Gameplay) |
| `misc_10` | Game Boy Wars 2 | CGB blue/white/yellow ramp visible in [Game Boy Wars 2 screenshots](https://gamesdb.launchbox-app.com/games/details/18491-game-boy-wars-2) |
| `misc_11` | Game Boy Wars 3 | brighter CGB blue/green/white ramp visible in [Game Boy Wars 3 screenshots](https://gamesdb.launchbox-app.com/games/details/18492-game-boy-wars-3); `E` remains a used-unit badge, not a cursor |

These are compatibility reconstructions rather than claims of a complete ROM
cursor rip. `Tools/build_cursor_atlases.py` is the reproducible assembler; it
draws the palette-specific map-frame angles and wrench badge while leaving the
unused arrow/X slots transparent, so the editor and playtest can share the
same map-frame geometry without showing AWDS-only pointer extras.

## Supplied ROM verification

The local `ROMs/` folder is now treated as extraction input, never as a
resource to bundle or commit. `Tools/ROMExtraction/extract_rom_graphics.py`
records the supplied cartridge hashes and writes native intermediates under
`.rom-extraction/` (also ignored by Git). The Super Famicom Wars cartridge was
decoded through its native LZN streams for static terrain, terrain icons, and
the 24 map-unit sprite streams. Game Boy Wars 3's native 2bpp unit block was
also extracted directly from the cartridge and matches the source-unit layout
used by `unit_11.png`.

Game Boy Wars 2's ROM graphics slice, CGB palette, and interleaved metatile
table are decoded into native terrain, property, and unit groups; its
normalized atlas uses the runtime group IDs selected by the map editor state.
Days of Ruin's NDS files and map NARCs are unpacked and the native Nitro LZ77
map textures are decoded before atlas assembly. To rebuild only these two
families after replacing either cartridge, run:

```sh
python3 Tools/ROMExtraction/extract_rom_graphics.py --rom-dir ROMs --output .rom-extraction
python3 Tools/ROMExtraction/assemble_atlases.py --games sfw,dor
```

Reference pages: [Super Famicom Wars map units](https://www.spriters-resource.com/snes/superfamicomwarsjpn/asset/125563/),
[Game Boy Wars 2](https://www.spriters-resource.com/game_boy_gbc/gameboywars2jpn/),
[Game Boy Wars 3](https://www.spriters-resource.com/game_boy_gbc/gbwars3/), and
[Days of Ruin](https://www.spriters-resource.com/ds_dsi/advwarsdor/).
