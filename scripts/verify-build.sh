#!/usr/bin/env bash
# Prove an exported build actually boots and runs its scripts.
#
# A successful export is not the same as a working build: Godot happily produces
# an executable that fails at startup, for example when the .pck is missing or a
# script has an error that only surfaces at runtime. This runs the exported
# Linux binary headless and requires it to print the smoke marker from
# src/build_smoke_test.gd.
#
# Only the Linux target can be verified this way, because that is the only
# target whose binary runs on the build machine. That still catches the failure
# modes that matter, since every target packages the same .pck contents.
#
# Usage: ./scripts/verify-build.sh
# Exit:  0 the build boots, 1 it does not.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

readonly SMOKE_MARKER="FEDERATION_SMOKE_OK"
readonly FRAMES=60

main() {
  load_target "linux"

  [[ -s "$TARGET_OUTPUT" ]] || die \
    "no linux build at $TARGET_OUTPUT. Run scripts/build.sh linux first."

  # A desktop export with embed_pck disabled needs its .pck beside the binary.
  # Shipping the binary alone was a real bug in this pipeline, so assert it.
  local pck="${TARGET_OUTPUT%.*}.pck"
  if [[ -f "$pck" ]]; then
    log "found $(basename "$pck") beside the binary"
  else
    warn "no .pck beside the binary. If embed_pck is disabled this build is broken."
  fi

  step "Booting $TARGET_OUTPUT headless for $FRAMES frames"
  local out status=0
  out="$(mktemp)"
  timeout 120 "$TARGET_OUTPUT" --headless --quit-after "$FRAMES" \
    >"$out" 2>&1 || status=$?

  # Print what the build said, so a failure is diagnosable from CI logs alone.
  sed 's/^/  | /' "$out" >&2

  if (( status >= 128 )); then
    rm -f "$out"
    die "build crashed on startup (exit $status, signal $((status - 128)))"
  fi

  if ! grep -q "$SMOKE_MARKER" "$out"; then
    rm -f "$out"
    die "build ran but never printed $SMOKE_MARKER.
       Its scripts did not reach the end of _ready(), so the package is
       incomplete or a script failed at runtime."
  fi

  rm -f "$out"
  step "Build boots and runs its scripts"
}

main "$@"
