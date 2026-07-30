#!/usr/bin/env bash
# Push built artifacts to itch.io with butler.
#
# Usage:
#   ./scripts/deploy-itch.sh                  # every target in ENABLED_TARGETS
#   ./scripts/deploy-itch.sh linux            # one target
#
# Environment:
#   BUTLER_API_KEY   required. An itch.io API key with upload rights.
#   DRY_RUN          set to 1 to validate everything and print the butler
#                    commands without uploading.
#
# Targets are resolved through the same lib/common.sh code that build.sh uses,
# so a channel can never drift from the artifact it is supposed to carry.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

readonly DRY_RUN="${DRY_RUN:-0}"

butler_run() {
  # butler ships alongside the shared libraries it needs for self updating.
  LD_LIBRARY_PATH="$(dirname "$BUTLER_BIN")" "$BUTLER_BIN" "$@"
}

push_target() {
  local name="$1" version="$2"
  load_target "$name"

  local push_path="$TARGET_OUTPUT"
  # Web and macOS ship as a directory of files; desktop targets ship one binary.
  # butler is happy with either, but pushing the directory keeps sibling files
  # (pck, data folders, wasm) together in the same build.
  if [[ "$name" == "web" || "$name" == "macos" ]]; then
    push_path="$(dirname "$TARGET_OUTPUT")"
  fi

  [[ -e "$push_path" ]] || die \
    "nothing to push for '$name' at $push_path. Run scripts/build.sh $name first."

  local slug="$ITCH_USER/$ITCH_GAME:$TARGET_CHANNEL"
  step "Pushing $name to $slug (version $version)"

  if [[ "$DRY_RUN" == "1" ]]; then
    log "DRY_RUN, would run:"
    log "butler push $push_path $slug --userversion $version"
    return 0
  fi

  butler_run push "$push_path" "$slug" --userversion "$version" \
    || die "butler push failed for $name
       If this is the first upload, confirm https://$ITCH_USER.itch.io/$ITCH_GAME
       exists. butler cannot create a project page."
}

main() {
  # Validate arguments first, same reasoning as build.sh.
  read_selected_targets "$@"
  local targets=("${SELECTED_TARGETS[@]}") version
  version="$(build_version)"

  [[ -x "$BUTLER_BIN" ]] || die \
    "butler not installed at $BUTLER_BIN. Run scripts/install-butler.sh first."

  if [[ "$DRY_RUN" != "1" ]]; then
    require_env BUTLER_API_KEY
    export BUTLER_API_KEY
  fi

  step "Deploying version $version to $ITCH_USER/$ITCH_GAME: ${targets[*]}"

  local name
  for name in "${targets[@]}"; do
    push_target "$name" "$version"
  done

  if [[ "$DRY_RUN" == "1" ]]; then
    step "Dry run complete, nothing uploaded"
    return 0
  fi

  step "Waiting for itch.io to finish processing"
  butler_run status "$ITCH_USER/$ITCH_GAME" >&2 || warn "could not read build status"

  step "Deploy complete: https://$ITCH_USER.itch.io/$ITCH_GAME"
}

main "$@"
