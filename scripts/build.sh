#!/usr/bin/env bash
# Export the Godot project for one or more targets.
#
# Usage:
#   ./scripts/build.sh                  # every target in ENABLED_TARGETS
#   ./scripts/build.sh linux            # one target
#   ./scripts/build.sh linux windows    # several
#
# Environment:
#   EXPORT_MODE   "release" (default) or "debug"
#
# This is the only place the project is exported. CI calls this script rather
# than reimplementing the export in workflow YAML, per CLAUDE.md section 4.1.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

readonly EXPORT_MODE="${EXPORT_MODE:-release}"

import_project() {
  step "Importing project"
  ensure_imported
  log "import complete"
}

build_target() {
  local name="$1"
  load_target "$name"

  step "Exporting $name ($TARGET_PRESET, $EXPORT_MODE)"

  # Clean the target's output directory so a stale artifact from a previous
  # build can never be mistaken for a fresh one and uploaded.
  #
  # This is an rm -rf on a computed path, so the path is proven to sit inside
  # BUILD_PATH first. Without the guard, an empty or malformed TARGET_OUTPUT
  # would make dirname return "." and wipe the working directory.
  local out_dir
  out_dir="$(dirname "$TARGET_OUTPUT")"
  case "$out_dir" in
    "$BUILD_PATH"/*) ;;
    *) die "refusing to clean '$out_dir': not inside $BUILD_PATH" ;;
  esac
  mkdir -p "$out_dir"
  rm -rf -- "${out_dir:?}"/*

  local flag="--export-release"
  [[ "$EXPORT_MODE" == "debug" ]] && flag="--export-debug"

  # Godot returns nonzero for export warnings as well as failures, so success
  # is judged by whether the artifact exists and is non-empty. run_godot still
  # aborts on a crash.
  run_godot --headless --path "$REPO_ROOT" \
    "$flag" "$TARGET_PRESET" "$TARGET_OUTPUT"

  [[ -s "$TARGET_OUTPUT" ]] || die \
    "export produced no artifact at $TARGET_OUTPUT
       Preset '$TARGET_PRESET' must exist in export_presets.cfg and its
       export templates must be installed. Re-run scripts/install-godot.sh."

  # Desktop binaries need the execute bit; itch's launcher relies on it.
  [[ "$TARGET_FILENAME" == *.exe || "$TARGET_FILENAME" == *.zip \
     || "$TARGET_FILENAME" == *.html ]] || chmod +x "$TARGET_OUTPUT"

  log "$(du -h "$TARGET_OUTPUT" | cut -f1)  $TARGET_OUTPUT"
}

main() {
  # Validate arguments before checking for tools, so a typo'd target name
  # reports the typo rather than a missing Godot install.
  read_selected_targets "$@"
  local targets=("${SELECTED_TARGETS[@]}")

  require_godot_project
  [[ -x "$GODOT_BIN" ]] || die \
    "Godot not installed at $GODOT_BIN. Run scripts/install-godot.sh first."
  require_dotnet_for_mono

  step "Building version $(build_version) for: ${targets[*]}"

  import_project

  local name
  for name in "${targets[@]}"; do
    build_target "$name"
  done

  step "Build complete"
  find "$BUILD_PATH" -type f -printf '  %s bytes  %p\n' >&2 2>/dev/null || true
}

main "$@"
