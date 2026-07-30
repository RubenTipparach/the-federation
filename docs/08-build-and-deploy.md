# 08. Build and Deploy

How the project gets from a commit to a playable build on itch.io.

---

## 1. Shape

```
   merge to main
        |
        v
  .github/workflows/deploy-itch.yml   (thin wrapper, no build logic)
        |
        +--> scripts/install-godot.sh    pinned Godot + export templates
        +--> scripts/install-butler.sh   itch.io upload tool
        +--> scripts/build.sh            Godot headless export, per target
        +--> scripts/deploy-itch.sh      butler push, per target
        |
        v
   https://rubentipparach.itch.io/the-federation
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
| Push to `main` | Builds and deploys `ENABLED_TARGETS`. Skipped for changes only under `docs/` or to `*.md`. |
| Manual dispatch | Optional target list, and a `dry_run` checkbox that builds and validates without uploading. |

Deploys run one at a time (`concurrency: deploy-itch`) and in progress runs are
**not** cancelled, because killing a half finished upload would leave a partial
build on itch.io.

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

| Target | Godot preset | itch channel | Enabled |
|---|---|---|---|
| `linux` | Linux | `linux` | yes |
| `windows` | Windows Desktop | `windows` | yes |
| `macos` | macOS | `osx` | no |
| `web` | Web | `html5` | no |

Channel names are chosen so itch.io auto detects the platform from the channel
name. Desktop targets push a single binary; `macos` and `web` push their whole
output directory, because those exports produce several files that belong to one
build.

Enabling a target is a one line change to `ENABLED_TARGETS`. `scripts/check-config.sh`
runs in CI and fails if a target names a preset that does not exist in
`export_presets.cfg`, which is otherwise a silent misconfiguration that can
upload an empty build.

---

## 6. Why macOS and Web are off

### Web is blocked by the C# decision, and this is a real trade

`docs/06-technical-architecture.md` section 2 selects **C# / .NET**, for a good
reason: one `TheFederation.Sim` library shared by the client, the combat server,
and the meta services, so the fitting screen and the battle resolve through the
same code.

That choice has a cost that lands squarely on itch.io. **Godot's .NET builds have
historically not supported Web export.** Web is the single biggest reason to ship
on itch at all: a browser playable build gets many times the engagement of a
download, and itch's discovery surfaces favor it.

So there is a genuine tension to resolve, and it is worth deciding deliberately
rather than by default:

1. **Keep C#, accept desktop only distribution on itch.** The shared sim library
   is preserved. The prototype reaches fewer people.
2. **Use GDScript for the client, C# only server side.** Restores Web export, but
   the fitting math and the combat sim would exist twice, in two languages. That
   is precisely the divergence CLAUDE.md section 4.1 forbids, and it is the worst
   option available.
3. **Keep C#, distribute the prototype elsewhere,** or ship desktop builds on itch
   and revisit Web when Godot's .NET Web support is production ready.

**Recommendation: option 1 for now, then re-evaluate at M2.** Prototype playtesting
per `docs/07-roadmap.md` M1 needs a handful of committed testers giving detailed
feedback, not casual browser traffic, and desktop builds serve that fine. The
decision only becomes expensive at M2, when the shipyard is worth showing widely.

**Verify before relying on either direction:** Godot's .NET Web export status has
been moving, and it was not possible to confirm the current state while writing
this (see section 7). Check the Godot documentation for the pinned version before
committing to a plan.

### macOS is off for signing reasons

Exporting macOS from a Linux runner produces an **unsigned** app. It runs, but
Gatekeeper shows a scary warning that a first time player will read as "this is
malware." Options are to sign properly (needs an Apple developer account and
certificates in CI), or to document the right click to open workaround. Neither
is worth doing before there is a game to install, so the preset exists and the
target is off.

---

## 7. What is verified and what is not

Stated plainly, because a deploy pipeline that claims to work and does not is
worse than one that is honest.

**Verified by running it:**
- `butler` installs from `broth.itch.zone` and runs. Confirmed v15.30.0.
- Target resolution, channel mapping, and the file versus directory push
  decision, through `DRY_RUN=1` with stand in artifacts.
- `scripts/check-config.sh` catches both a target with no table row and a preset
  renamed out from under a target. Negative tested, not just happy path.
- Version stamping from `git describe`, with the untagged fallback.
- All scripts pass `bash -n` and `shellcheck --severity=warning`.
- Both workflow files parse as valid YAML.

**Not verified, and needs a first real run:**
- **The Godot half.** `github.com` and `api.github.com` return 403 from the
  authoring session's egress proxy, so Godot could not be downloaded and no
  export was ever executed. `scripts/install-godot.sh`, the archive layout
  handling, and the whole export path are written from the documented behavior
  and are untested.
- **The pinned Godot version.** `GODOT_VERSION=4.5` in `build.config` could not
  be confirmed to exist. `install-godot.sh` prints the URL it tried on failure,
  so a wrong pin is a loud, one line fix.
- **`export_presets.cfg`.** Hand written, where Godot normally generates it.
  Open the project in the editor once and let it re-save the file, so any option
  keys that differ in the pinned version get corrected. The preset **names** and
  `export_path` values are what must survive that round trip, since
  `build.config` refers to them.
- **The itch.io project page.** `butler` cannot create one. The first push fails
  until https://rubentipparach.itch.io/the-federation exists.

The first `main` build should be run via manual dispatch with `dry_run` checked.

---

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
3. Add the name to `ENABLED_TARGETS`.
4. Run `./scripts/check-config.sh`, then `./scripts/build.sh <name>`, then
   `DRY_RUN=1 ./scripts/deploy-itch.sh <name>`.

No script or workflow changes are needed. If a new target requires one, that is
a signal the shared code needs a parameter rather than a fork.
