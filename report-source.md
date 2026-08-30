# Legacy playtest command-rail research

Research date: 2026-08-26

Scope: visual treatment and command vocabulary for the in-editor legacy
playtest rail. The rail is an editor affordance; it is not a claim that the
original cartridges used a permanent left-side panel.

## Evidence ledger

| Game | Evidence | Design conclusion |
| --- | --- | --- |
| Famicom Wars | [Nintendo's Famicom Wars archive](https://www.nintendo.com/jp/famicom/software/hvc-fw/index.html), [Nintendo manual](https://www.nintendo.co.jp/data/software/manual/man_FDWJ_00.pdf), and the [4Gamer gameplay screenshot](https://www.4gamer.net/games/999/G999905/20240418034/SS/003.jpg) | Use a compact black map-command surface, crisp square pixel rules, a pale yellow/olive active item, and white text. The original lower command strip is horizontal, so a vertical editor rail should stay dense and avoid modern card chrome. |
| Super Famicom Wars | [Nintendo Virtual Console command reference](https://www.nintendo.co.jp/wii/vc/vc_sfw/vc_sfw_07.html), [Nintendo manual](https://www.nintendo.co.jp/data/software/manual/235310.pdf), and the command-window capture ([Nintendo image](https://www.nintendo.co.jp/wii/vc/vc_sfw/img/page_07/07_ph_a.gif)) | Use a dark vertical command window with a cyan/blue multi-rule frame, white pixel lettering, and a pale yellow/olive selected row. Keep information and unit-command groups visually separate from production. |
| Game Boy Wars / TURBO | [Original Game Boy manual scan](https://gbdbstorage.s3.amazonaws.com/manuals/dmg/DMG-AGWJ-JPN_Ja_0.pdf) and the [retro gameplay screenshot set](https://mimora.mimoza.jp/yao_game/retro/contents/ctg_main/memorandum/GB/detail/gmr_GB-0029.php) | Use a monochrome DMG palette: black outlines, off-white/pale-green surfaces, teal separators, square corners, and compact type. Keep controls and status information dense. |
| Game Boy Wars 2 | [Hardcore Gaming 101's series analysis](https://www.hardcoregaming101.net/game-boy-wars-series/) says its interface is the original GB Wars interface in color; compare the [MobyGames menu screenshot](https://www.mobygames.com/game/59384/game-boy-wars-2/screenshots/gameboy-color/623853/) and [UVList battle/map gallery](https://www.uvlist.net/gallery/?game=101382). | Retain the original GB Wars geometry, but switch to a restrained Game Boy Color navy/cream/teal palette. Do not give it the later GB Wars 3 rail. |
| Game Boy Wars 3 | [Hudson's contemporaneous Game Watch coverage](https://game.watch.impress.co.jp/docs/20010827/hudson.htm) and its [menu screenshot](https://game.watch.impress.co.jp/docs/20010827/hudson02.jpg) | Give it its own tall left menu: white rows, heavy navy outline, blue inner rules, and a green/cream active treatment. The screenshot is visibly unlike GB Wars 1/2 and unlike the GBA games. |
| Advance Wars | [Advance Wars strategy guide](https://gamefaqs.gamespot.com/gba/471043-advance-wars/faqs/13909) and the [GBA map-menu screenshot](https://i.imgur.com/ETzUTfr.png) | Use the familiar peach/orange GBA map menu, dark navy/charcoal outline, icon-like leading markers, and a muted lavender active row. Preserve the six high-level map commands (Unit, Intel, Power, Save, Options, End) in the visual hierarchy even though this editor exposes extra context actions. |
| Advance Wars 2 | [Nintendo's Advance Wars 2 manual](https://www.nintendo.com/eu/media/downloads/games_8/emanuals/game_boy_advance_8/Manual_GameBoyAdvance_AdvanceWars2BlackHoleRising_EN_DE_FR_ES_IT.pdf) (map-menu section) and the [Advance Wars 2 gameplay reference image](https://koopanique.neocities.org/video_games/video_games_pictures/advance_wars2.JPG) | Keep the AW1 GBA menu geometry, add the sequel's cooler blue/steel edge treatment, and make Intel/Power/Save/Options/End read as a coherent map-menu stack. |

## Synthesis

There are three visual families rather than one universal skin:

1. Famicom/Super Famicom: black or dark maroon pixel windows with layered
   console-era borders and an olive/yellow active row.
2. Game Boy: square, high-contrast panels. Original/2 are dense DMG/GBC status
   boxes; 3 is a distinct blue-and-white vertical menu.
3. GBA: warm peach map menus with dark blue/charcoal outlines and icon-led
   rows. AW2 is a cooler sequel variation, not a DS-style surface.

The implementation keeps the existing action model and keyboard semantics but
gives each `Tileset` a rail palette, frame, type scale, row treatment, header,
and footer. This keeps the editor's English labels usable while preserving the
visual grammar supported by the original screenshots and manuals.
