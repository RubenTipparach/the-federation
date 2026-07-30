#!/usr/bin/env bash
# Validate that build.config and export_presets.cfg agree.
#
# Catches the silent misconfigurations the pipeline is prone to:
#   1. A name in ENABLED_TARGETS or DEPLOY_TARGETS with no row in TARGETS.
#   2. A target whose Godot preset does not exist in export_presets.cfg.
#   3. A target that is deployed but never built, which fails at upload time
#      with a missing artifact rather than at config time.
#
# All would otherwise surface as a confusing mid-build failure, or worse, as
# an empty artifact that uploads successfully.
#
# Usage: ./scripts/check-config.sh
# Exit:  0 consistent, 1 mismatch.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
load_config

failures=0

fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }
pass() { printf 'ok    %s\n' "$*"; }

step "Checking ENABLED_TARGETS and DEPLOY_TARGETS against the TARGETS table"
for list in ENABLED_TARGETS DEPLOY_TARGETS; do
  for name in ${!list}; do
    if resolve_target "$name" >/dev/null 2>&1; then
      pass "$list target '$name' is defined"
    else
      fail "$list names '$name', which has no row in TARGETS"
    fi
  done
done

step "Checking every deployed target is also built"
for name in $DEPLOY_TARGETS; do
  found=0
  for built in $ENABLED_TARGETS; do
    [[ "$built" == "$name" ]] && found=1 && break
  done
  if [[ "$found" == 1 ]]; then
    pass "deploy target '$name' is in ENABLED_TARGETS"
  else
    fail "DEPLOY_TARGETS names '$name', which ENABLED_TARGETS does not build.
      The upload would fail on a missing artifact."
  fi
done

step "Checking Godot presets against export_presets.cfg"
presets_file="$REPO_ROOT/export_presets.cfg"
if [[ ! -f "$presets_file" ]]; then
  fail "export_presets.cfg not found at repository root"
else
  # Preset names appear as: name="Windows Desktop"
  mapfile -t declared < <(
    grep -oP '(?<=^name=")[^"]+' "$presets_file" 2>/dev/null || true
  )
  printf '  presets in export_presets.cfg: %s\n' "${declared[*]:-none}" >&2

  while read -r name; do
    [[ -z "$name" ]] && continue
    load_target "$name"
    found=0
    for d in "${declared[@]:-}"; do
      [[ "$d" == "$TARGET_PRESET" ]] && found=1 && break
    done
    if [[ "$found" == 1 ]]; then
      pass "target '$name' -> preset '$TARGET_PRESET'"
    else
      fail "target '$name' wants preset '$TARGET_PRESET', not in export_presets.cfg"
    fi
  done < <(known_targets)
fi

step "Checking the Godot project exists"
if [[ -f "$REPO_ROOT/project.godot" ]]; then
  pass "project.godot present"
else
  fail "project.godot not found at repository root"
fi

if [[ "$failures" -gt 0 ]]; then
  printf '\n%d problem(s) found.\n' "$failures" >&2
  exit 1
fi

printf '\nConfig is consistent.\n'
