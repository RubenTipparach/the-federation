#!/usr/bin/env bash
#
# shellcheck disable=SC2034
# SC2034 is disabled for this file only. It reports "appears unused" for the
# variables this library exists to define (GODOT_BIN, TARGET_CHANNEL,
# SELECTED_TARGETS and friends). ShellCheck analyses one file at a time and
# cannot see that the scripts sourcing this file are the consumers.
#
# Shared helpers for every script in scripts/.
#
# Per CLAUDE.md section 4.1, config loading, target resolution, and version
# stamping exist exactly once, here. build.sh and deploy-itch.sh both resolve
# targets through resolve_target(), so a target can never mean one thing to the
# builder and something else to the deployer.
#
# Not executable on its own. Source it:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -euo pipefail

# --- Paths -------------------------------------------------------------------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPO_ROOT

# --- Logging -----------------------------------------------------------------

# All diagnostics go to stderr so that a function's stdout stays parseable.
log()  { printf '  %s\n'      "$*" >&2; }
step() { printf '\n==> %s\n'  "$*" >&2; }
warn() { printf 'WARN: %s\n'  "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# --- Config ------------------------------------------------------------------

load_config() {
  local config="$REPO_ROOT/build.config"
  [[ -f "$config" ]] || die "missing config: $config"
  # shellcheck source=/dev/null
  source "$config"

  local required=(
    GODOT_VERSION GODOT_RELEASE GODOT_FLAVOR
    ITCH_USER ITCH_GAME
    ENABLED_TARGETS DEPLOY_TARGETS TARGETS
    BUILD_DIR TOOLS_DIR
  )
  local name
  for name in "${required[@]}"; do
    [[ -n "${!name:-}" ]] || die "build.config does not set $name"
  done

  case "$GODOT_FLAVOR" in
    mono|standard) ;;
    *) die "GODOT_FLAVOR must be 'mono' or 'standard', got '$GODOT_FLAVOR'" ;;
  esac

  # Absolute, so scripts work from any working directory.
  BUILD_PATH="$REPO_ROOT/$BUILD_DIR"
  TOOLS_PATH="$REPO_ROOT/$TOOLS_DIR"

  # Godot names its export template directory after the version, with a
  # ".mono" suffix for the .NET flavor.
  GODOT_TEMPLATE_VERSION="$GODOT_VERSION.$GODOT_RELEASE"
  [[ "$GODOT_FLAVOR" == "mono" ]] && GODOT_TEMPLATE_VERSION+=".mono"

  GODOT_BIN="$TOOLS_PATH/godot/godot"
  BUTLER_BIN="$TOOLS_PATH/butler/butler"
}

# --- Targets -----------------------------------------------------------------

# Print the TARGETS row for a target name, pipe delimited with fields trimmed.
# Returns 1 without printing if the target is unknown. Deliberately does NOT
# die: callers that want to report several bad targets at once (check-config.sh)
# need to keep going, and a die() here would abort on the first one.
# Usage: row="$(resolve_target linux)" || handle_unknown
resolve_target() {
  local want="$1" name preset subdir filename channel
  while IFS='|' read -r name preset subdir filename channel; do
    name="$(trim "$name")"
    [[ -z "$name" || "$name" == \#* ]] && continue
    if [[ "$name" == "$want" ]]; then
      printf '%s|%s|%s|%s\n' \
        "$(trim "$preset")" "$(trim "$subdir")" \
        "$(trim "$filename")" "$(trim "$channel")"
      return 0
    fi
  done <<< "$TARGETS"
  return 1
}

# The message every caller should use when resolve_target fails, so the wording
# exists once.
unknown_target_error() {
  printf "unknown target '%s'. Known targets: %s" \
    "$1" "$(known_targets | tr '\n' ' ')"
}

known_targets() {
  local name rest
  while IFS='|' read -r name rest; do
    name="$(trim "$name")"
    [[ -z "$name" || "$name" == \#* ]] && continue
    printf '%s\n' "$name"
  done <<< "$TARGETS"
}

# Read the fields of a target into the caller's scope.
# Sets: TARGET_PRESET TARGET_SUBDIR TARGET_FILENAME TARGET_CHANNEL TARGET_OUTPUT
load_target() {
  local name="$1" row
  row="$(resolve_target "$name")" || die "$(unknown_target_error "$name")"
  IFS='|' read -r TARGET_PRESET TARGET_SUBDIR TARGET_FILENAME TARGET_CHANNEL \
    <<< "$row"
  TARGET_OUTPUT="$BUILD_PATH/$TARGET_SUBDIR/$TARGET_FILENAME"
}

# Populate the global SELECTED_TARGETS array, aborting the calling script if
# any requested target is unknown.
#
# Usage: read_selected_targets "$ENABLED_TARGETS" "$@"
# The first argument is the default list to use when the caller passed no
# target names. It is explicit because build.sh and deploy-itch.sh default to
# different lists: everything that gets built is not necessarily everything
# that gets published.
#
# Callers must use this rather than reading selected_targets through a process
# substitution. In `mapfile -t x < <(selected_targets ...)` the function runs in
# a subshell, so its die() cannot stop the parent: the script would print the
# error, carry on with an empty target list, and fail later for an unrelated
# looking reason. Command substitution propagates the failure correctly.
read_selected_targets() {
  local raw
  raw="$(selected_targets "$@")" || exit 1
  mapfile -t SELECTED_TARGETS <<< "$raw"
}

# Targets requested on the command line, else the caller's default list.
# Validates every name before returning any, so a typo fails before work starts.
selected_targets() {
  local fallback="$1"
  shift
  local requested=("$@") name
  [[ ${#requested[@]} -eq 0 ]] && read -r -a requested <<< "$fallback"
  [[ ${#requested[@]} -eq 0 ]] && die "no targets requested and the default target list is empty"
  for name in "${requested[@]}"; do
    resolve_target "$name" >/dev/null || die "$(unknown_target_error "$name")"
  done
  printf '%s\n' "${requested[@]}"
}

# --- Version -----------------------------------------------------------------

# The version string stamped onto itch.io builds via butler --userversion.
# Prefers a git tag, falls back to a commit count plus short sha so that
# untagged builds still sort sensibly in itch's build list.
build_version() {
  if [[ -n "${BUILD_VERSION:-}" ]]; then
    printf '%s\n' "$BUILD_VERSION"
    return
  fi
  if ! git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    printf '0.0.0-unknown\n'
    return
  fi
  local described
  if described="$(git -C "$REPO_ROOT" describe --tags --dirty 2>/dev/null)"; then
    printf '%s\n' "${described#v}"
  else
    printf '0.0.0-r%s-%s\n' \
      "$(git -C "$REPO_ROOT" rev-list --count HEAD)" \
      "$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  fi
}

# --- Guards ------------------------------------------------------------------

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  printf '%s' "${s%"${s##*[![:space:]]}"}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_env() {
  [[ -n "${!1:-}" ]] || die "required environment variable not set: $1"
}

# The .NET build of Godot does not fail cleanly when the SDK is absent: it
# segfaults (SIGSEGV, exit 134) while still creating a partial .godot/
# directory, even for a project containing no C# files at all. Verified against
# Godot 4.7.1.stable.mono. Check up front so the failure names its cause.
require_dotnet_for_mono() {
  [[ "$GODOT_FLAVOR" != "mono" ]] && return 0
  command -v dotnet >/dev/null 2>&1 || die \
    "GODOT_FLAVOR is 'mono' but dotnet is not on PATH.
       Godot's .NET build crashes rather than erroring cleanly without it.
       Install the .NET SDK (${DOTNET_VERSION:-8.0.x}), or set
       GODOT_FLAVOR=\"standard\" in build.config if the project has no C# yet."
}

# Run Godot, tolerating the nonzero status it returns for benign export
# warnings, but never tolerating a crash.
#
# A status of 128+N means the process died on signal N. Treating every nonzero
# status as "probably just warnings" would silently accept a segfault, which is
# exactly the failure mode observed when dotnet is missing.
run_godot() {
  local status=0
  "$GODOT_BIN" "$@" >&2 || status=$?
  if (( status >= 128 )); then
    die "Godot crashed with exit $status (signal $((status - 128))) running:
       $GODOT_BIN $*"
  fi
  return 0
}

# Godot must generate .godot/ before any export or script run will behave. On
# a clean checkout it does not exist. 4.7.1 aborts if --import runs against a
# cold project, so the cold pass is primed with --editor --quit first, and only
# then is --import run with its exit status trusted. Shared by build.sh and
# run-tests.sh so the workaround exists once.
ensure_imported() {
  if [[ ! -d "$REPO_ROOT/.godot" ]]; then
    log "cold project, priming the import with --editor --quit"
    "$GODOT_BIN" --headless --path "$REPO_ROOT" --editor --quit >&2 || true
  fi
  run_godot --headless --path "$REPO_ROOT" --import
  [[ -d "$REPO_ROOT/.godot" ]] || die "import did not produce .godot/, cannot continue"
}

require_godot_project() {
  [[ -f "$REPO_ROOT/project.godot" ]] \
    || die "no project.godot at repository root, nothing to export"
  [[ -f "$REPO_ROOT/export_presets.cfg" ]] \
    || die "no export_presets.cfg at repository root. Open the project in the
       Godot editor once and configure the export presets named in build.config."
}
