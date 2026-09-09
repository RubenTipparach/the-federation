#!/usr/bin/env bash
# Enforce the writing rule from CLAUDE.md section 1: zero em dashes (U+2014)
# and zero en dashes (U+2013) anywhere in the repository.
#
# The characters are matched by codepoint so this script itself stays clean
# ASCII and does not report itself.
#
# The include list is every kind of text this repository writes, because the
# rule says the WHOLE repository and a checker that only looks at nine
# extensions quietly stops being that. Python, JSON, HTML and Godot resources
# were the four it used to miss, and the fleet generators are Python.
#
# Usage: ./scripts/check-style.sh
# Exit:  0 clean, 1 violations found.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# LC_ALL is required: \x{...} above 0x7F needs a UTF-8 locale.
if LC_ALL=C.UTF-8 grep -rnP '\x{2014}|\x{2013}' \
     --include='*.md' --include='*.cs' --include='*.gd' --include='*.tscn' \
     --include='*.cfg' --include='*.yml' --include='*.yaml' --include='*.sh' \
     --include='*.config' --include='*.godot' --include='*.py' \
     --include='*.json' --include='*.html' --include='*.tres' \
     --exclude-dir='.git' --exclude-dir='.godot' \
     --exclude-dir='.tools' --exclude-dir='builds' .; then
  printf '\nFAIL: em dash (U+2014) or en dash (U+2013) found above.\n' >&2
  printf 'See CLAUDE.md section 1. Use a colon, a comma, a period, or a\n' >&2
  printf 'plain hyphen for ranges.\n' >&2
  exit 1
fi

printf 'PASS: no em dashes or en dashes found.\n'
