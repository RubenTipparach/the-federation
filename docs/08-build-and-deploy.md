# 08. Build and Deploy

How the project gets from a commit to a playable build on itch.io.

---

## 1. Shape

```
   merge to main
        |
        v
  .github/workflows/deploy-itch.yml   (thin wrapper, no build logic)
        |    job "Style and scripts", then job "Build and deploy"
        |
        +--> scripts/install-godot.sh    pinned Godot + export templates
        +--> scripts/install-butler.sh   itch.io upload tool
        +--> scripts/build.sh            Godot headless export, per target
        +--> scripts/deploy-itch.sh      butler push, per target
        |
        v
   https://ruben-tipparach.itch.io/federation
```

**The workflow contains no build logic.** Every step calls a committed script,
and those same scripts are what a developer runs locally. This is CLAUDE.md
section 4.1 applied to CI: if the build lived in workflow YAML, local builds and
CI builds would be two implementations of the same thing, and they would drift.
The failure mode that prevents is the classic one, "it works on my machine but
not in CI," which is almost always a divergence bug rather than an environment
bug.

`build.config` is the only place versions, targets, and itch.io coordinates are
written down, per CLAUDE.md section 5.4.

---

## 2. Local use

```sh
./scripts/install-godot.sh          # once, or after changing the pinned version
./scripts/install-butler.sh         # once

./scripts/build.sh                  # every target in ENABLED_TARGETS
./scripts/build.sh linux            # just one
EXPORT_MODE=debug ./scripts/build.sh linux

DRY_RUN=1 ./scripts/deploy-itch.sh  # validate and print, upload nothing
BUTLER_API_KEY=... ./scripts/deploy-itch.sh
```

Both installers are idempotent, so re-running them costs nothing. Everything
lands in `.tools/` and `builds/`, both git ignored.

Use `DRY_RUN=1` before any real upload. It resolves targets, checks the
artifacts exist, and prints the exact `butler push` commands without touching
itch.io.

---

## 3. Triggers

| Trigger | Behavior |
|---|---|
| Push to `main` | Checks, builds, verifies, and **deploys**. |
| Pull request | Checks, builds, and verifies. **Never deploys.** Catches a broken export in the pull request instead of on merge. |
| Manual dispatch | Optional target list, and a `dry_run` checkbox that builds and validates without uploading. |

**One run per commit.** The triggers are disjoint on purpose: `pull_request`
covers every feature branch, `push` covers `main`, and nothing is subscribed to
both. An earlier layout split the checks into a second workflow file that
listened on `pull_request` while this one listened on branch pushes, so one
commit started two runs, and a merge started two more. Everything now lives in
this file as two jobs, and the build job runs only if the checks job passes.

There is no `paths-ignore` filter. A documentation only change costs about a
minute of cached build time, which is cheaper than maintaining a rule that
decides when verification may be skipped, and it means no change can reach
`main` without the export having been built from it.

The deploy step is gated on `github.ref == 'refs/heads/main'`, so a pull
request cannot publish to itch.io even with the secret available.

Note that `workflow_dispatch` only becomes available once this workflow file
exists on the default branch.

Runs are grouped per ref. A superseded pull request run is cancelled, since its
result no longer matters, but a `main` run is never cancelled: killing a half
finished upload would leave a partial build on itch.io.

Artifacts upload to the workflow run regardless of whether the itch.io push
succeeds, so a failed deploy still leaves something to inspect.

---

## 4. Secrets

| Secret | Used by | Status |
|---|---|---|
| `BUTLER_API_KEY` | itch.io upload | **Required.** Set in repository settings. |
| `FLY_API_TOKEN` | Fly.io deploy | **Reserved, not used yet.** See section 8. |

Get `BUTLER_API_KEY` from https://itch.io/user/settings/api-keys and add it under
Settings > Secrets and variables > Actions.

**If `BUTLER_API_KEY` is absent the workflow does not fail.** It builds, uploads
the artifacts to the run, emits a warning, and skips the push. This keeps the
pipeline useful before the secret is configured, and means a rotated or expired
key produces a clear warning rather than a confusing build failure.

---

## 5. Targets and channels

From the `TARGETS` table in `build.config`:

| Target | Godot preset | itch channel | Built | Published |
|---|---|---|---|---|
| `web` | Web | `html5` | yes | **yes, and first class** |
| `linux` | Linux | `linux` | yes | no, verification only |
| `windows` | Windows Desktop | `windows` | no | no |
| `macos` | macOS | `osx` | no | no, see below |

`web` is listed first because it is the priority target: on itch.io a browser
playable build reaches far more people than a download.

**Built and published are two different lists.** `ENABLED_TARGETS` is what
`build.sh` exports, `DEPLOY_TARGETS` is what `deploy-itch.sh` uploads, and the
second must be a subset of the first. They differ on purpose: the desktop
downloads are paused, so only `web` is published, but `linux` is still exported
because `verify-build.sh` boots that binary headless to prove the package runs.
It is the only target whose binary runs on the build machine, and every target
packages the same `.pck` contents, so dropping it would cost the boot check for
all of them.

Resuming a desktop download is a one word change: put the name back in both
lists. `check-config.sh` fails the build if a name appears in `DEPLOY_TARGETS`
but not in `ENABLED_TARGETS`, which would otherwise surface as an upload of a
missing artifact.

Turning a channel off here stops future uploads. It does not remove what is
already on itch.io: previously pushed `windows` and `linux` builds stay on the
project page until they are deleted there, which butler cannot do.

Channel names are chosen so itch.io auto detects the platform from the channel
name. **Every target pushes its whole output directory**, never a single file: a
desktop export produces the executable plus a separate `.pck`, and shipping the
executable alone uploads a build that cannot start. See section 7.

Enabling a target is a one line change to `ENABLED_TARGETS`. `scripts/check-config.sh`
runs in CI and fails if a target names a preset that does not exist in
`export_presets.cfg`, which is otherwise a silent misconfiguration that can
upload an empty build.

---

## 6. Web is first class, and what that decided

### The C# question is settled, against C#

An earlier draft of this pipeline used Godot's .NET build, because
`docs/06-technical-architecture.md` wanted C# for a shared simulation library.
**That is reversed.** A browser playable build on itch.io matters more, and Godot
4's .NET build cannot produce one. This is not a guess: 4.7.1 refuses outright.

```
ERROR: Cannot export project with preset "Web" due to configuration errors:
Exporting to Web is currently not supported in Godot 4 when using C#/.NET.
Use Godot 3 to target Web with C#/Mono instead.
If this project does not use C#, use a non-C# editor build to export the project.
```

So `GODOT_FLAVOR="standard"` and the project is GDScript.

**The shared simulation requirement survives intact**, because the sharing comes
from the engine rather than the language: the authoritative combat server is a
headless Godot export of this same project, so it runs the identical GDScript
files the client runs. See `docs/06-technical-architecture.md` section 2 for the
full argument and the two things genuinely given up.

Switching back, if a browser build ever stops mattering, is one word in
`build.config`. The expensive part would be porting the sim, not the tooling.

### Web export settings that matter

- **`variant/thread_support=false`.** Godot's threaded Web export needs
  `SharedArrayBuffer`, which needs COOP and COEP response headers that itch.io
  only sends when a project explicitly enables its SharedArrayBuffer option.
  Threads off means the build runs anywhere with no special configuration. If
  that option is enabled on the itch project later, flipping this to `true` is
  worth doing for performance.
- **`gl_compatibility` renderer**, set in `project.godot`. Vulkan does not run in
  a browser, so `forward_plus` would produce a build that fails at startup.

### itch.io page setup for the web build

butler uploads the files, but it cannot configure the page. On the project's edit
page, the `html5` channel's build must be set as **"This file will be played in
the browser"**, and an embed size chosen (the project is authored at 1600x900).
Without that, itch offers the web build as a download instead of playing it.

### macOS is off for signing reasons

Exporting macOS from a Linux runner produces an **unsigned** app. It runs, but
Gatekeeper shows a warning a first time player will read as "this is malware."
Fixing it properly needs an Apple developer account and certificates in CI.
Not worth doing before there is a game to install, so the preset exists and the
target stays off.

---

## 7. What is verified

The pipeline was exercised end to end on a real Godot install, not just written.

**Verified by running it:**
- **Godot 4.7.1.stable installs and runs.** Downloaded from Godot's own
  endpoint, `downloads.godotengine.org`, which is what godotengine.org/download
  links to. Preferred over the GitHub releases URLs because it is canonical and
  stays reachable where egress policy blocks github.com.
- **Real exports of all three enabled targets** from `export_presets.cfg` as
  committed: Web (39 MB `index.wasm` plus `index.html`, `index.js`, `index.pck`),
  Windows (105 MB plus a .pck), Linux (71 MB plus a .pck).
- **The Web export specifically**, which is the whole reason for the GDScript
  decision. `index.html` sits at the output root and references the wasm, js, and
  pck, which is the layout itch.io needs.
- **The exported build boots and runs its scripts.** `scripts/verify-build.sh`
  runs the Linux binary headless and requires it to print its smoke marker. An
  export succeeding is not the same as a build that works.
- `butler` installs from `broth.itch.zone` and runs. v15.30.0.
- Target resolution, channel mapping, and directory push contents, via
  `DRY_RUN=1`.
- `scripts/check-config.sh` negative tested: it catches both a target with no
  table row and a preset renamed out from under a target.
- All scripts pass `bash -n` and `shellcheck --severity=warning`. Both workflows
  parse.

**Four real bugs were found by running it, and fixed:**

1. **The deploy shipped broken builds.** With `binary_format/embed_pck` disabled,
   a desktop export produces the executable *and* a separate `.pck` holding all
   game data. The deploy pushed only the executable, so the uploaded build could
   not start. It now always pushes the target's whole output directory, which is
   correct for every target and removes a per target special case rather than
   adding one.
2. **A crashed import counted as success.** Two separate crashes hid behind the
   old check, which only looked for `.godot/` existing:
   - The .NET build segfaults (SIGSEGV) when the SDK is absent, even with no C#
     files, and still leaves a partial `.godot/` behind.
   - Godot 4.7.1 **aborts** (SIGABRT, `Parameter "singleton" is null` in
     `is_cmdline_mode`) when `--import` runs against a project that has no
     `.godot/` yet. A cold checkout, which is every CI run.

   There is now a `run_godot` wrapper that treats any exit status of 128 or above
   as a crash, so both are caught rather than swallowed. The cold import is
   primed with `--editor --quit`, which handles a fresh project correctly, and
   only then is `--import` run and its status trusted.
3. **Changing the Godot version or flavor kept the old editor.** The install was
   idempotent on "does the binary exist," so switching from mono to standard
   silently kept the mono editor and would have failed against the new templates.
   It now records the installed version in a stamp file and replaces a mismatch.
4. **An `rm -rf` on a computed path** could have expanded to `./*`. Flagged by
   shellcheck; the path is now proven to sit inside `builds/` first.

**Added when the prototype landed (2026-07-30):**
- `scripts/run-tests.sh` runs the 91 check headless sim suite; CI runs it before any
  export. The suite runs on a cold checkout, because the cold import priming now lives
  in `lib/common.sh` and is shared by build and tests.
- The Web build was driven in Chromium via Playwright: smoke marker observed in the
  browser console, every screen screenshotted, a live battle ran, zero Godot script
  errors. This is how the grid transparency sorting bug and the plan inset world
  sharing bug were caught.

**Still unverified:**
- **The upload itself.** `butler push` has not run against itch.io from here,
  because the API key correctly lives only in repository secrets. The first
  deploy from `main` is the real test.
- **The Web build actually running in a browser.** It exports correctly and has
  the right file layout, but it has not been loaded in a browser. The first
  deploy is the real test.
- **The macOS export.** Preset exists, target disabled. See section 6.
- `export_presets.cfg` was hand written and Godot accepted it, but the editor has
  not re-saved it. Opening the project once and letting the editor rewrite the
  file is still worth doing, so any option keys Godot silently ignored get
  corrected. The preset **names** and `export_path` values must survive that.

## 8. Fly.io: deliberately deferred

`FLY_API_TOKEN` is reserved and **no Fly.io pipeline exists yet.** This is a
decision, not an oversight: the server architecture should not be built until
the prototype mechanics are understood.

The reasoning holds up against the roadmap. `docs/07-roadmap.md` puts networking
at **M4**, three milestones after the tactical prototype, and M1 is explicitly
local with no server at all. Building a deploy pipeline for a server whose shape
is still unknown would mean guessing at the battle instance lifecycle, and then
rewriting it once the real tick rate, state size, and session model are known.

When it is time, `docs/06-technical-architecture.md` section 10 has the intended
topology. The pipeline should follow the same rule as this one: thin workflow,
logic in committed scripts, configuration in `build.config`.

---

## 9. Adding a target

1. Add a preset in the Godot editor. Note its exact name.
2. Add a row to `TARGETS` in `build.config`.
3. Add the name to `ENABLED_TARGETS`, and to `DEPLOY_TARGETS` as well if the
   target should be published rather than only built.
4. Run `./scripts/check-config.sh`, then `./scripts/build.sh <name>`, then
   `DRY_RUN=1 ./scripts/deploy-itch.sh <name>`.

No script or workflow changes are needed. If a new target requires one, that is
a signal the shared code needs a parameter rather than a fork.
