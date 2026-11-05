#!/usr/bin/env bash
# Compile the puzzles to WebAssembly (needs emcc on PATH).
# Output: web/wasm/<name>.js + <name>.wasm
set -euo pipefail
cd "$(dirname "$0")"

P=vendor/puzzles
OUT=web/wasm
mkdir -p "$OUT"

CORE="combi.c divvy.c draw-poly.c drawing.c dsf.c findloop.c grid.c
  latin.c laydomino.c loopgen.c malloc.c matching.c midend.c misc.c
  penrose.c penrose-legacy.c ps.c random.c sort.c tdq.c tree234.c
  version.c hat.c spectre.c"
CORE_SRC=$(for f in $CORE; do echo "$P/$f"; done)

PUZZLES="${*:-bridges keen loopy pattern}"
EXPORTS='["_malloc","_free"]'

for name in $PUZZLES; do
  echo "building $name"
  emcc -O2 -flto \
    -I"$P" -Wno-unused-function \
    src/frontend.c $CORE_SRC "$P/$name.c" \
    --js-library src/library.js \
    -s MODULARIZE=1 -s EXPORT_ES6=1 -s EXPORT_NAME="create_$name" \
    -s ENVIRONMENT=web,worker \
    -s ALLOW_MEMORY_GROWTH=1 -s STACK_SIZE=1048576 \
    -s EXPORTED_FUNCTIONS="$EXPORTS" \
    -s EXPORTED_RUNTIME_METHODS='["cwrap","UTF8ToString"]' \
    -s FILESYSTEM=0 -s ASSERTIONS=0 \
    -o "$OUT/$name.js"
done
ls -la "$OUT"
