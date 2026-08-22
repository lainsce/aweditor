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

  Famicom Wars exposes Red Star, White Moon, Green Soil, and Yellow Star in
  the editor and playtest; Black Hole is omitted because it is not a Famicom
  Wars army.

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
  Dual Strike-only Extra tab. The unit atlas uses the matching [Famicom
  Wars units extraction](https://www.spriters-resource.com/nes/famicomwarsjpn/asset/11798/),
  fitted into AWED's 16-pixel unit cells. Famicom's four playable faction
  rows are retained; unsupported fifth-army rows are remapped to Red Star so
  no purple Black Hole army art leaks into a Famicom map, while neutral
  property rows remain neutral. Every opaque pixel in the unit and building
  sheets is normalized to a valid colour from the NTSC 2C02 PPU's 64-entry
  palette. Populated historical unit/property frames use the exact Famicom
  Plains green `(72,168,16)` as their ground plate, while unused atlas slots
  remain transparent. Every 16×16 Famicom unit cell also carries a one-pixel
  black rule along its final row and column. The river slots are hand-pixeled
  directional variants (straight, turns, tees, and cross), derived from the two
  source River_NS rhythms instead of repeating one vertical cell.
- The `_7` sheets use the supplied 16×16 Game Boy Wars tile references as a
  four-tone source. `terrain_7.png` follows the compact 16×8 square-cell
  layout of the `_6` terrain guide: active cells are opaque gray/black art and
  unused atlas slots remain transparent. `unit_7.png` follows the existing
  `unit_6.png` silhouettes with strict black/white ordered dithering: rows 0–1
  are black-dominant Red Star, and rows 2–3 are white-dominant White Moon
  with a one-pixel black silhouette outline for legibility.
  The other army rows remain transparent because GB Wars only exposes those
  two playable armies. GB property art is 16×16, but its faction rows are
  stored on a two-row cadence in `building_7.png`; the renderer maps those
  rows explicitly instead of treating the buildings as 16×32. These are
  reference-derived GB Wars approximations, not a claim to be a canonical
  full ROM rip.

The historical sheets intentionally replace the prior palette-recolor
fallback. They preserve the source silhouettes and layout selected from those
references while applying the source system's palette constraints and the
Famicom ground treatment; transparent extra-object cells indicate that the
original extract did not provide an equivalent AWED/DS extra-object table.
