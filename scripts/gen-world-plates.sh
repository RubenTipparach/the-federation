#!/usr/bin/env bash
# Regenerate the world concept plates in docs/images/worlds/.
#
# Two steps, because the art is a vendored shader's output: Godot draws each
# world into its own viewport and writes it at native size, then a Python pass
# magnifies and arranges those into the plates docs/15-worlds.md shows. There is
# no second implementation of the planet art here to draw from, and there must
# not be (CLAUDE.md 4.1), so the renders come from the running game or they do
# not come at all.
#
# It needs a rendering context to draw a viewport, so it runs under xvfb rather
# than --headless, the same as scripts/bench-ui.sh.
#
# Run it after changing the worlds role map in data/palette.json, the planet
# scenes under scenes/terrain/, or the vendored shaders.
#
# Usage: ./scripts/gen-world-plates.sh
# Exit:  0 the plates were written, 1 otherwise.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

main() {
  [[ -x "$GODOT_BIN" ]] || die \
    "Godot not installed at $GODOT_BIN. Run scripts/install-godot.sh first."
  command -v xvfb-run >/dev/null || die \
    "xvfb-run not found. Drawing a viewport needs a rendering context."
  require_godot_project
  ensure_imported

  step "Rendering the worlds"
  local out status=0
  out="$(mktemp)"
  xvfb-run -a "$GODOT_BIN" --path "$REPO_ROOT" --rendering-driver opengl3 \
    --script res://tools/shoot_worlds.gd >"$out" 2>&1 || status=$?

  # Godot complains about the absent sound card on every machine without one,
  # which is every CI runner. Only the harness's own lines are wanted.
  grep '^WORLD' "$out" | sed 's/^/  /' >&2

  if ! grep -q "WORLDS_DONE" "$out"; then
    sed 's/^/  /' "$out" >&2
    rm -f "$out"
    die "the render did not finish (exit $status)"
  fi
  rm -f "$out"

  step "Composing the plates"
  python3 "$REPO_ROOT/tools/gen_world_plates.py"

  step "Plates written to docs/images/worlds/"
}

main "$@"
