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

  # Always push the target's whole output directory, never the single artifact.
  #
  # This is not a convenience. With binary_format/embed_pck disabled, a Godot
  # desktop export produces the executable AND a separate .pck holding all game
  # data. Pushing only the executable uploads a build that cannot start.
  # Verified: a linux export produced the-federation.x86_64 plus
  # the-federation.pck, and an earlier version of this script shipped only the
  # former. Web and macOS exports likewise spread across several files.
  #
  # Pushing the directory is correct for every target, so there is no per target
  # special case to get wrong.
  local push_path
  push_path="$(dirname "$TARGET_OUTPUT")"

  # The primary artifact is what proves the export ran, so check for it by name
  # rather than just checking that the directory exists.
  [[ -s "$TARGET_OUTPUT" ]] || die \
    "nothing to push for '$name': $TARGET_OUTPUT is missing or empty.
       Run scripts/build.sh $name first."

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
