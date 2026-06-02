#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

V_BIN="${V_BIN:-v}"
SMOKE=0
SMOKE_SECS="${SMOKE_SECS:-8}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --smoke)
      SMOKE=1
      shift
      ;;
    --seconds)
      SMOKE_SECS="${2:-8}"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage:
  scripts/test_examples.sh            # compile-check all examples
  scripts/test_examples.sh --smoke    # compile-check + smoke run each example
  scripts/test_examples.sh --smoke --seconds 10

Environment:
  V_BIN       Override V executable (default: v)
  SMOKE_SECS  Smoke timeout seconds (default: 8)
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if ! command -v "$V_BIN" >/dev/null 2>&1; then
  echo "Error: V compiler not found: $V_BIN" >&2
  exit 1
fi

CC_FLAGS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  # Work around tcc/Metal issues on macOS.
  CC_FLAGS=(-cc clang)
fi

examples=(
  "examples/rotating_v_logo.v"
  "examples/v_logo_obj_3d.v"
  "examples/gx_gears_like.v"
  "examples/doom_demo.v"
  "examples/galaga_style.v"
  "examples/tetris_game.v"
  "examples/flappy_webgpu.v"
)

echo "== Compile checks =="
for f in "${examples[@]}"; do
  echo "-- $f"
  "$V_BIN" -check "$f"
done

echo "Compile checks: OK"

if [[ "$SMOKE" -ne 1 ]]; then
  exit 0
fi

echo

echo "== Smoke run checks (${SMOKE_SECS}s each) =="
for f in "${examples[@]}"; do
  echo "-- $f"
  log_file="$(mktemp)"
  set +e
  "$V_BIN" "${CC_FLAGS[@]}" run "$f" >"$log_file" 2>&1 &
  run_pid=$!
  set -e

  elapsed=0
  interval=1
  while kill -0 "$run_pid" >/dev/null 2>&1; do
    if [[ "$elapsed" -ge "$SMOKE_SECS" ]]; then
      kill -TERM "$run_pid" >/dev/null 2>&1 || true
      wait "$run_pid" >/dev/null 2>&1 || true
      echo "   launched (timeout reached)"
      rm -f "$log_file"
      continue 2
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done

  set +e
  wait "$run_pid"
  exit_code=$?
  set -e
  if [[ "$exit_code" -eq 0 ]]; then
    echo "   exited cleanly"
    rm -f "$log_file"
    continue
  fi

  echo "   FAILED with exit code $exit_code" >&2
  cat "$log_file" >&2
  rm -f "$log_file"
  exit "$exit_code"
done

echo "Smoke runs: OK"
