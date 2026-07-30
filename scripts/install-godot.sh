#!/usr/bin/env bash
# Install the headless Godot editor and its export templates into TOOLS_DIR.
#
# Version, release, and flavor all come from build.config so that CI and a
# developer's machine install the identical toolchain.
#
# Idempotent: exits early if the pinned version is already present.
#
# Usage: ./scripts/install-godot.sh

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

readonly RELEASE_BASE="https://github.com/godotengine/godot/releases/download"

# Godot's release assets are named differently for the two flavors.
editor_archive_name() {
  if [[ "$GODOT_FLAVOR" == "mono" ]]; then
    printf 'Godot_v%s-%s_mono_linux_x86_64.zip' "$GODOT_VERSION" "$GODOT_RELEASE"
  else
    printf 'Godot_v%s-%s_linux.x86_64.zip' "$GODOT_VERSION" "$GODOT_RELEASE"
  fi
}

templates_archive_name() {
  if [[ "$GODOT_FLAVOR" == "mono" ]]; then
    printf 'Godot_v%s-%s_mono_export_templates.tpz' "$GODOT_VERSION" "$GODOT_RELEASE"
  else
    printf 'Godot_v%s-%s_export_templates.tpz' "$GODOT_VERSION" "$GODOT_RELEASE"
  fi
}

fetch() {
  local url="$1" out="$2"
  log "downloading $url"
  # On failure, name the URL. A wrong version pin in build.config is the most
  # likely cause and this makes it a one line fix rather than a hunt.
  curl -sSL --fail --retry 3 --retry-delay 2 -o "$out" "$url" || die \
    "download failed: $url
       Check GODOT_VERSION, GODOT_RELEASE, and GODOT_FLAVOR in build.config
       against the actual Godot release assets."
}

install_editor() {
  step "Installing Godot $GODOT_VERSION-$GODOT_RELEASE ($GODOT_FLAVOR)"
  local dest archive tag
  dest="$(dirname "$GODOT_BIN")"
  mkdir -p "$dest"
  archive="$dest/godot.zip"
  tag="$GODOT_VERSION-$GODOT_RELEASE"

  fetch "$RELEASE_BASE/$tag/$(editor_archive_name)" "$archive"
  unzip -q -o "$archive" -d "$dest" || die "Godot archive did not unpack"
  rm -f "$archive"

  # The mono archive unpacks into a nested directory; the standard one is a
  # bare binary. Normalize both to a single predictable path.
  local found
  found="$(find "$dest" -type f \( -name 'Godot_v*' -o -name 'godot*' \) \
    ! -name '*.zip' ! -name 'godot' -print -quit)"
  [[ -n "$found" ]] || die "no Godot executable found under $dest"

  if [[ "$found" != "$GODOT_BIN" ]]; then
    # Keep the mono runtime files next to the binary by moving the whole
    # directory contents up, not just the executable.
    local srcdir
    srcdir="$(dirname "$found")"
    if [[ "$srcdir" != "$dest" ]]; then
      mv "$srcdir"/* "$dest"/
      rmdir "$srcdir" 2>/dev/null || true
      found="$dest/$(basename "$found")"
    fi
    mv "$found" "$GODOT_BIN"
  fi
  chmod +x "$GODOT_BIN"

  log "installed to $GODOT_BIN"
  "$GODOT_BIN" --headless --version >&2 || die "Godot installed but will not run"
}

install_templates() {
  step "Installing export templates ($GODOT_TEMPLATE_VERSION)"
  # Godot looks for templates in this exact path. It is not configurable.
  local template_dir="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_VERSION"
  mkdir -p "$template_dir"

  local tmp archive
  tmp="$(mktemp -d)"
  archive="$tmp/templates.tpz"
  fetch "$RELEASE_BASE/$GODOT_VERSION-$GODOT_RELEASE/$(templates_archive_name)" \
    "$archive"

  # A .tpz is a zip whose contents live under a single "templates" directory.
  unzip -q -o "$archive" -d "$tmp" || die "template archive did not unpack"
  [[ -d "$tmp/templates" ]] || die "template archive layout unexpected, no templates/ dir"
  mv "$tmp/templates"/* "$template_dir"/
  rm -rf "$tmp"

  log "installed $(find "$template_dir" -maxdepth 1 -type f | wc -l) template files"
  log "to $template_dir"
}

main() {
  require_cmd curl
  require_cmd unzip
  require_cmd find

  local template_dir="$HOME/.local/share/godot/export_templates/$GODOT_TEMPLATE_VERSION"

  if [[ -x "$GODOT_BIN" ]] && [[ -d "$template_dir" ]] \
     && [[ -n "$(ls -A "$template_dir" 2>/dev/null)" ]]; then
    step "Godot $GODOT_TEMPLATE_VERSION and templates already installed"
    return 0
  fi

  [[ -x "$GODOT_BIN" ]] || install_editor
  if [[ ! -d "$template_dir" ]] || [[ -z "$(ls -A "$template_dir" 2>/dev/null)" ]]; then
    install_templates
  fi
}

main "$@"
