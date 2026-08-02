#!/usr/bin/env bash
# Measure what the interface costs per frame, in microseconds of CPU.
#
# The debug overlay in the running game answers "how slow is it"; this answers
# "which call". It times the HUD refresh directly rather than watching frames,
# so no rasteriser is involved and the numbers mean the same thing on every
# machine. See the header of tests/bench_ui.gd for what it found and why.
#
# It needs a rendering context to build the scene, so it runs under xvfb rather
# than --headless: Control nodes will not lay out or report sizes without one.
#
# Usage: ./scripts/bench-ui.sh
# Exit:  0 the benchmark ran, 1 otherwise.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

main() {
  [[ -x "$GODOT_BIN" ]] || die \
    "Godot not installed at $GODOT_BIN. Run scripts/install-godot.sh first."
  command -v xvfb-run >/dev/null || die \
    "xvfb-run not found. The benchmark needs a rendering context to lay out Controls."
  require_godot_project
  ensure_imported

  step "Benchmarking the interface"
  local out status=0
  out="$(mktemp)"
  xvfb-run -a "$GODOT_BIN" --path "$REPO_ROOT" --rendering-driver opengl3 \
    --script res://tests/bench_ui.gd >"$out" 2>&1 || status=$?

  # Godot writes audio driver complaints to stderr on a machine with no sound
  # card, which is every CI runner. Only the benchmark's own lines are wanted.
  sed -n '/^PER FRAME$/,/^BENCH_DONE$/p' "$out" | sed 's/^/  /' >&2

  if ! grep -q "BENCH_DONE" "$out"; then
    sed 's/^/  /' "$out" >&2
    rm -f "$out"
    die "benchmark did not finish (exit $status)"
  fi
  rm -f "$out"
  step "Benchmark complete"
}

main "$@"
