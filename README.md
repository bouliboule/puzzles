# Puzzles

A touch-first PWA for six puzzles from [Simon Tatham's Portable Puzzle
Collection](https://www.chiark.greenend.org.uk/~sgtatham/puzzles/):
**Loopy**, **Bridges**, **Keen**, **Pattern**, **Pearl** and **Slant**. The original C generators
and solvers are compiled to WebAssembly; the UI is new and designed for
phones, tablets and e-ink readers.

## Features

- Works offline once installed (Add to Home Screen on iOS, Install on Android).
- Tap/drag input with a mode switch (e.g. Line/Cross, Number/Notes) and
  long-press for the secondary action. Pinch or the magnifier buttons to zoom,
  two fingers to pan.
- On-screen keypad for Keen.
- Puzzles are generated in a Web Worker and the next one is pre-generated,
  so "New game" is instant even for 15×22 Loopy on slow devices.
- Auto-save per puzzle, timer, solve counts.
- Themes: light, dark, and **e-ink** (pure greyscale palette, no animation,
  heavier strokes, partial redraws only) — pick it under App settings on a
  Boox or other e-ink device.
- Game IDs to move a puzzle between devices.

Defaults: Loopy 15×22 Hard, Bridges 15×22 Hard, Keen 6×6 Normal, Pattern 20×20, Pearl 10×10 Tricky,
Slant 8×8 Hard.

## Develop

Needs [Emscripten](https://emscripten.org) (`brew install emscripten`).

```sh
./build.sh            # compiles vendor/puzzles → web/wasm/
python3 dev-server.py # http://localhost:8642
```

`src/frontend.c` is a small midend-driven front end exporting `pz_*`
functions; `src/library.js` forwards drawing calls to `web/js/engine.js`.

## Deploy

Pushing to `main` runs `.github/workflows/deploy.yml`, which builds the
WebAssembly and publishes `web/` to GitHub Pages (set Pages → Source to
"GitHub Actions").

## Android

A native app in `android/`: the same C puzzle code built with the NDK
through `src/native/pz.c` (a handle-based C API meant to be shared with
the iOS/macOS app), with Kotlin + Jetpack Compose UI and a custom
`View` for the board.

On a Mac (Apple Silicon is fine):

```sh
brew install openjdk@17 && brew install --cask android-commandlinetools
export JAVA_HOME=/opt/homebrew/opt/openjdk@17 ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
sdkmanager "platform-tools" "platforms;android-35" "build-tools;35.0.0" "ndk;27.2.12479018" "cmake;3.22.1"
cd android
./gradlew assembleDebug     # app/build/outputs/apk/debug/app-debug.apk
./gradlew assembleRelease   # signed with android/keystore.properties if present, else the debug key
adb install -r app/build/outputs/apk/release/app-release.apk
```

For Google Play, use `./gradlew bundleRelease` (an `.aab`) with a real
upload key in `android/keystore.properties` (`storeFile`, `storePassword`,
`keyAlias`, `keyPassword`).

## iOS, iPadOS and macOS

A native SwiftUI app in `apple/` (one multiplatform target): the same C
puzzle code through `src/native/pz.h`, drawn with Core Graphics into a
layer-backed board view. Touch, Apple Pencil, long press, pinch zoom,
hardware keyboards, and on the Mac right-click, trackpad pinch/scroll
and a Game menu with shortcuts (⌘N new, ⌘Z/⇧⌘Z undo/redo).

Needs Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`); the `.xcodeproj` is generated, not committed.

```sh
cd apple
xcodegen                    # writes Puzzles.xcodeproj
open Puzzles.xcodeproj      # pick an iPhone simulator or "My Mac", then Run
```

Or from the command line:

```sh
xcodebuild -project Puzzles.xcodeproj -scheme Puzzles -destination 'platform=macOS' -derivedDataPath build/dd build
xcodebuild -project Puzzles.xcodeproj -scheme Puzzles -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
```

Simulator and Mac builds need no Apple team (the Mac app is signed ad
hoc). To run on a device or ship, set `DEVELOPMENT_TEAM` in
`apple/project.yml` and remove the two `[sdk=macosx*]` signing overrides.
`apple/tools/make-icon.swift` regenerates the app icons.

## Licence

MIT. Puzzle engine © Simon Tatham and contributors, MIT (see `vendor/puzzles/LICENCE`).
