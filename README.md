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

## Licence

MIT. Puzzle engine © Simon Tatham and contributors, MIT (see `vendor/puzzles/LICENCE`).
