#!/usr/bin/env bash
# Repaint the UI skin from data/palette.json.
#
# The plate textures and the themes are both build products of that file, so
# they are regenerated together and never edited by hand. A skin belongs to a
# faction, so this writes one deck per entry in "ui_factions": the plates land
# in assets/ui/skin/<faction>/ and the theme beside them as
# assets/ui/skin_theme_<faction>.tres. To change a deck:
#
#   1. point a faction in "ui_factions" at a different skin in data/palette.json
#   2. run this
#
# The font is not regenerated: it is a white alpha mask tinted per control, so
# one atlas serves every skin. Run tools/gen_font.py only when the glyphs
# themselves change.
#
# Build logic lives in scripts/ so CI and developers run the same thing
# (CLAUDE.md 8).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

python3 tools/gen_ui_plates.py
python3 tools/gen_theme.py

echo
echo "==> Skin regenerated. Godot reimports the .png on next open or build."
