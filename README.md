# Underwater Diver Controller

A separate diver edition of [underwater_scrolling_background](https://github.com/ssrose-b/underwater_scrolling_background), retaining its underwater tile map and VGA timing.

[Open in VGA Playground](https://vga-playground.com/?repo=https://github.com/ssrose-b/underwater-diver-controller)

## Controller inputs

Connect active-high direction buttons to the existing `ui_in` controller inputs:

| Input | Action |
| --- | --- |
| `ui_in[0]` | Swim left |
| `ui_in[1]` | Swim right |
| `ui_in[2]` | Swim up |
| `ui_in[3]` | Swim down |
| `ui_in[4]` | Hold for fast swim |

Use the corresponding input toggles/controller mappings in VGA Playground. This project accepts digital directions; it does not implement a USB, Bluetooth or serial gamepad decoder. A physical controller needs an adapter to these five inputs.

The diver swims at 2 pixels per frame, or 4 while fast swim is held. Diagonals are supported; opposing directions cancel independently on each axis. The diver faces the last horizontal direction and animates its fins while swimming. Release all directions to stop. Reset (`rst_n=0`) returns the diver to its starting position. `ena=0` pauses movement.

## Rendering

- 640x480 RGB222 VGA at a 25.175 MHz pixel clock.
- Original 1280x960 world, 80x60 map of 16x16 tiles.
- Original pixel-art diver, 16x16 pixels displayed at 2x scale.
- Camera follows the diver and stops at world edges; the diver can then move toward the screen edge.
- Position updates happen in vertical blank. Sprite transparency and color are delayed by two clocks to match the background ROM pipeline.
- Rock tiles (192–207) and sand tiles (128) are solid. The full 32x32 diver bounds stop at them; diagonal movement slides along walls without clipping corners. Plants, coral, bubbles and wreck tiles remain decorative.

Collision reads `data/map.mem` directly, just like the background renderer. Tile 128 is the original `assets/seabed-sand.png`; tiles 192–207 are all original `assets/rocky-seabed.png` quadrant/transform variants. There is no separately generated collision map to become out of sync with the visible terrain.

## Run simulation

With Icarus Verilog installed, run from the repository root:

```sh
cd src
iverilog -g2012 -Wall -s diver_tb -o /tmp/diver_tb project.v hvsync_generator.v ../tests/diver_tb.v
vvp /tmp/diver_tb
```

The test checks movement in all directions, camera follow, opposite directions, diagonal fast swim, enable, world boundaries, and transparent/opaque sprite pixels.

## Assets and provenance

Original background source and commit history are retained from `ssrose-b/underwater_scrolling_background` (base commit `29bc41d758754d9742a37e2e9b7e07ad39dd9788`). Existing background asset credits are in [ASSETS.md](ASSETS.md). The new diver artwork is original and dedicated to the public domain under CC0 1.0; see [assets/DIVER-LICENSE.md](assets/DIVER-LICENSE.md). The upstream repository supplies no general code license; this asset dedication applies only to the new diver artwork.
