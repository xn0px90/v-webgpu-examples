# v-webgpu-examples

Visual WebGPU-oriented V examples.

## Install dependency

Install the WebGPU module from VPM:

```bash
v install xn0px90.webgpu
```

## Run examples

```bash
v run examples/rotating_v_logo.v
v run examples/v_logo_obj_3d.v
v run examples/gx_gears_like.v
v run examples/doom_demo.v
v run examples/galaga_style.v
v run examples/tetris_game.v
v run examples/flappy_webgpu.v
```

On macOS, prefer clang explicitly:

```bash
v -cc clang run examples/rotating_v_logo.v
```

If `v run` fails with `file 'Metal' not found`, use `-cc clang`.

## Run and test all examples

Compile-check all examples:

```bash
scripts/test_examples.sh
```

Compile-check plus smoke-run all examples:

```bash
scripts/test_examples.sh --smoke --seconds 6
```

See [examples/examples.md](examples/examples.md) for details.

## Windows Setup Fix

After running `v install xn0px90.webgpu`, the module installs under 
`xn0px90/webgpu` but examples use `import webgpu`. 

**Fix** — run this in an Administrator PowerShell once:

```powershell
New-Item -ItemType SymbolicLink `
  -Path "$env:USERPROFILE\.vmodules\webgpu" `
  -Target "$env:USERPROFILE\.vmodules\xn0px90\webgpu"
```

Then run examples from the repo root:
```powershell
v run examples/rotating_v_logo.v
```

Tested on: Windows 11, V 0.5.1, NVIDIA GPU