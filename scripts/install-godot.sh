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

# Godot's own download endpoint, which is what godotengine.org/download links
# to. Preferred over github.com/godotengine/godot/releases because it is the
# canonical entry point, it redirects to Godot's object storage, and it stays
# reachable in environments whose egress policy blocks github.com.
readonly DOWNLOAD_BASE="https://downloads.godotengine.org"

# Build a download URL for one asset slug.
asset_url() {
  local slug="$1" platform="$2"
  printf '%s/?version=%s&flavor=%s&slug=%s&platform=%s' \
    "$DOWNLOAD_BASE" "$GODOT_VERSION" "$GODOT_RELEASE" "$slug" "$platform"
}

# Asset slugs differ between the two flavors.
editor_url() {
  if [[ "$GODOT_FLAVOR" == "mono" ]]; then
    asset_url "mono_linux_x86_64.zip" "linux.64"
  else
    asset_url "linux.x86_64.zip" "linux.64"
  fi
}

templates_url() {
  if [[ "$GODOT_FLAVOR" == "mono" ]]; then
    asset_url "mono_export_templates.tpz" "templates"
  else
    asset_url "export_templates.tpz" "templates"
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
       against the versions listed at https://godotengine.org/download/linux/"
}

install_editor() {
  step "Installing Godot $GODOT_VERSION-$GODOT_RELEASE ($GODOT_FLAVOR)"
  local dest archive
  dest="$(dirname "$GODOT_BIN")"
  mkdir -p "$dest"
  archive="$dest/godot.zip"

  fetch "$(editor_url)" "$archive"
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
  fetch "$(templates_url)" "$archive"

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
  # Records which version and flavor the installed editor actually is. Without
  # it, "the binary exists" was the only check, so changing GODOT_VERSION or
  # GODOT_FLAVOR in build.config silently kept the old editor and produced
  # confusing export failures against the new templates.
  local stamp
  stamp="$(dirname "$GODOT_BIN")/.installed-version"

  local installed=""
  [[ -f "$stamp" ]] && installed="$(cat "$stamp")"

  if [[ -x "$GODOT_BIN" ]] && [[ "$installed" == "$GODOT_TEMPLATE_VERSION" ]] \
     && [[ -d "$template_dir" ]] && [[ -n "$(ls -A "$template_dir" 2>/dev/null)" ]]; then
    step "Godot $GODOT_TEMPLATE_VERSION and templates already installed"
    return 0
  fi

  if [[ -x "$GODOT_BIN" ]] && [[ "$installed" != "$GODOT_TEMPLATE_VERSION" ]]; then
    step "Installed editor is '${installed:-unknown}', want '$GODOT_TEMPLATE_VERSION'"
    log "removing the stale editor"
    rm -rf -- "${TOOLS_PATH:?}/godot"
  fi

  [[ -x "$GODOT_BIN" ]] || { install_editor; printf '%s' "$GODOT_TEMPLATE_VERSION" > "$stamp"; }
  if [[ ! -d "$template_dir" ]] || [[ -z "$(ls -A "$template_dir" 2>/dev/null)" ]]; then
    install_templates
  fi
}

main "$@"
