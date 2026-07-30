#!/usr/bin/env bash
# Run the headless simulation test suite in tests/run_tests.gd.
#
# The suite exercises the sim library without instantiating a scene, which is
# the property CLAUDE.md section 5.2 requires of it. CI runs this before any
# export, and it is the same entry point a developer uses locally.
#
# Usage: ./scripts/run-tests.sh
# Exit:  0 all checks pass, 1 otherwise.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

main() {
  [[ -x "$GODOT_BIN" ]] || die \
    "Godot not installed at $GODOT_BIN. Run scripts/install-godot.sh first."
  require_dotnet_for_mono
  require_godot_project
  ensure_imported

  step "Running simulation tests"
  local out status=0
  out="$(mktemp)"
  "$GODOT_BIN" --headless --path "$REPO_ROOT" \
    --script res://tests/run_tests.gd >"$out" 2>&1 || status=$?
  sed 's/^/  /' "$out" >&2

  if (( status >= 128 )); then
    rm -f "$out"
    die "test run crashed (exit $status)"
  fi
  if ! grep -q "ALL TESTS PASSED" "$out"; then
    rm -f "$out"
    die "simulation tests failed"
  fi
  rm -f "$out"
  step "Simulation tests pass"
}

main "$@"
