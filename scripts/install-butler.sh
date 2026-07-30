#!/usr/bin/env bash
# Install butler, the itch.io upload tool, into TOOLS_DIR.
#
# Idempotent: exits early if the pinned binary is already present, so it is
# cheap to call on every CI run and safe to call locally.
#
# Usage: ./scripts/install-butler.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

readonly BUTLER_CHANNEL="linux-amd64"
readonly BUTLER_URL="https://broth.itch.zone/butler/${BUTLER_CHANNEL}/LATEST/archive/default"

main() {
  require_cmd curl
  require_cmd unzip

  if [[ -x "$BUTLER_BIN" ]]; then
    step "butler already installed"
    "$BUTLER_BIN" -V >&2 || true
    return 0
  fi

  step "Installing butler"
  local dest archive
  dest="$(dirname "$BUTLER_BIN")"
  mkdir -p "$dest"
  archive="$dest/butler.zip"

  log "downloading $BUTLER_URL"
  curl -sSL --fail --retry 3 --retry-delay 2 -o "$archive" "$BUTLER_URL" \
    || die "butler download failed from $BUTLER_URL"

  unzip -q -o "$archive" -d "$dest" || die "butler archive did not unpack"
  rm -f "$archive"

  # The archive ships butler plus the libraries it needs for self updating.
  chmod +x "$BUTLER_BIN"
  [[ -x "$BUTLER_BIN" ]] || die "butler binary missing after unpack: $BUTLER_BIN"

  log "installed to $BUTLER_BIN"
  LD_LIBRARY_PATH="$dest" "$BUTLER_BIN" -V >&2 \
    || die "butler installed but will not run"
}

main "$@"
