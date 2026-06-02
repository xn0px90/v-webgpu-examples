# v-webgpu examples

This repository contains visual examples that use the `xn0px90.webgpu` V module.

## Install dependency

```bash
v install xn0px90.webgpu
```

## macOS note

If `v run` fails with `file 'Metal' not found`, run examples with clang explicitly:

```bash
v -cc clang run examples/rotating_v_logo.v
```

## Visual examples

## 1) Rotating V logo

File: `examples/rotating_v_logo.v`

```bash
v run examples/rotating_v_logo.v
```

## 2) 3D OBJ V logo

File: `examples/v_logo_obj_3d.v`

Downloads and caches the model at `examples/assets/v-logo-3d.obj` on first run.

```bash
v run examples/v_logo_obj_3d.v
```

## 3) GX-gears-like demo

File: `examples/gx_gears_like.v`

Three animated interlocking gears rendered in a style similar to classic `gx` gears demos.

```bash
v run examples/gx_gears_like.v
```

## 4) Doom-style raycaster demo

File: `examples/doom_demo.v`

Classic software-raycaster style corridor demo with movement controls.

```bash
v run examples/doom_demo.v
```

Controls:

- `W/S`: move forward/back
- `A/D`: turn left/right
- `Q/E`: strafe left/right
- `ESC`: close

## 5) Galaga-style arcade game

File: `examples/galaga_style.v`

Arcade-style wave shooter with enemy formation movement, player bullets, lives, and score.

```bash
v run examples/galaga_style.v
```

Controls:

- `A/D` or arrows: move
- `Space`: shoot
- `R`: restart after game over/stage clear
- `ESC`: close

## 6) Tetris-style puzzle game

File: `examples/tetris_game.v`

Classic falling-block puzzle with piece rotation, hard drop, line clears, scoring, and levels.

```bash
v run examples/tetris_game.v
```

Controls:

- `A/D` or arrows: move left/right
- `Up`/`W`/`X`: rotate
- `Down`/`S`: soft drop
- `Space`: hard drop
- `P`: pause
- `R`: restart
- `ESC`: close

## 7) Flappy-style arcade game

File: `examples/flappy_webgpu.v`

Arcade bird-and-pipes game with score tracking, restart, and collision logic.

```bash
v run examples/flappy_webgpu.v
```

Controls:

- `Space`/`Up`/`W`: flap
- `R`: restart
- `ESC`: close

## Notes

- Import path in code is `import webgpu` (module provided by `xn0px90.webgpu`).
- You need a native WebGPU implementation installed on your machine.
- Run all checks with `scripts/test_examples.sh`.
- Smoke-run all examples with `scripts/test_examples.sh --smoke --seconds 6`.
