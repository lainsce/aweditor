# AW Map Editor — SwiftUI port

AW Map Editor is a native macOS SwiftUI port of the original wxWidgets Advance Wars
Series Map Editor. This port is new work; the original editor was written by
Joao Pedro S. Francese (Roma_emu). The original `wxAWDSMapEd/` source and the
format/readme documents remain as compatibility references.

The Advance Wars game assets and bundled music are by Intelligent Systems.
This project is an unofficial, unaffiliated editor and does not claim ownership
of those assets or music. See [LICENSE.md](LICENSE.md) for the source-license
and trademark notice.

The app targets macOS 27.0 and newer and is delivered as a native Xcode
project (`AW Map Editor.xcodeproj`). It requires Xcode 27 or newer.

Build the app from the command line:

```sh
xcodebuild -project "AW Map Editor.xcodeproj" -scheme "AW Map Editor" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO build
```

Run the core tests:

```sh
xcodebuild -project "AW Map Editor.xcodeproj" -scheme "AW Map Editor" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO test
```

Build a runnable app bundle with the helper script:

```sh
./Scripts/package-app.sh
open "Build/DerivedData/Build/Products/Debug/AW Map Editor.app"
```

The port reads and writes `.awm`, `.aw2`, `.awd`, and variable-size `.aws`
maps, preserves the documented metadata fields, and warns before lossy legacy
format conversion. Xcode copies the sprite sheets and bundled BGM tracks into
the application bundle. Dual Strike variants use `bgm.mp3`, Advance Wars 1/2
use `bgm_2.mp3`, Famicom Wars uses `bgm_3.mp3`, and GB Wars uses `bgm_4.mp3`.
The music follows the Preferences enable/volume controls and loops while the
editor is open. Preferences also toggle the
original AW-style tile frames and allowed/forbidden/delete pointer glyphs; the
cursor setting applies immediately to the map canvas.

The canvas retains the original secondary mouse shortcuts: right-click picks
the active terrain/unit, middle-click advances Terrain → Unit → Extra, and the
scroll wheel cycles the selected building or unit's army. Command/Control-drag
copies a selection while Option-drag advances terrain sprites and Shift allows
multiple HQs.

Save Screenshot supports PNG, BMP, JPG, XPM, and ICO output, with full-size,
half-size, and miniature image-size choices.
