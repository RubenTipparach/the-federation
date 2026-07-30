# 06. Technical Architecture (Godot 4 + Fly.io)

> **Note on scope:** this is a pre-production architecture proposal. Version numbers,
> platform limits, and pricing below are starting assumptions to be **verified against
> current Fly.io and Godot documentation before committing**. Several are flagged inline.

---

## 1. Constraints That Shape Everything

Four properties of *this* game determine the architecture. Get these right and the rest
follows.

1. **Combat is slow.** Capital ships take seconds to turn. There is no twitch aiming, no
   headshot, no sub-100ms decision. **This is enormous.** It means we do not need rollback
   netcode, client-side prediction of other players, or UDP heroics. A 10-15 Hz
   server-authoritative tick with client-side interpolation is *fully sufficient*, and that
   single fact removes most of the hard problems from a normally-hard genre.
2. **Combat is instanced and bounded.** ≤24 capital ships, ≤30 minutes, fixed participant
   list. Battles are **ephemeral, isolated, horizontally scalable compute**, the single
   best fit imaginable for Fly Machines' start-on-demand model.
3. **The galaxy is slow.** Hex movement is minutes. Trade ticks are minutes. Colony growth
   is hours. The persistent layer is a **database with a scheduler**, not a realtime sim.
4. **The shipyard is offline-safe.** Fitting, queues, markets, and colony management are
   ordinary transactional CRUD over HTTP. No realtime requirement whatsoever.

**Architectural conclusion:** one hard realtime problem (bounded, instanced, slow-tick),
surrounded by a large amount of unremarkable web-service work. Do not over-engineer the
second part.

---

## 2. Language & Engine Recommendation

**Recommendation: Godot 4 with C# (.NET), and .NET for the backend services.**

Rationale: the decisive factor is **sharing the simulation code**:

- The combat sim, the fitting validator, and the damage model must produce *identical*
  results in the client (for prediction, dry-dock simulation, and the fitting UI's derived
  stats) and on the server (authoritative). Implementing them twice guarantees divergence
  bugs that are miserable to find.
- With Godot's .NET build, `TheFederation.Sim` can be a **plain .NET class library**
  referenced by the Godot client, the headless combat server, *and* the meta service. The
  fitting screen's projected stats are computed by literally the same code that resolves the
  battle.
- C# also handles this game's data-heavy math (four-budget validation, internal damage
  tables, arc geometry) with far better performance and refactoring safety than GDScript.

Use **GDScript for UI glue and scene scripting** where it's faster to write: the shipyard's
interaction layer, menus, effects. Keep all rules in C#.

**Alternative considered:** GDScript client + Elixir/Phoenix meta server. Elixir is
genuinely the better tool for tens of thousands of persistent connections and supervised
world processes. **Rejected for the first two years** because it adds a third language, and
because the shared-sim-code benefit above outweighs Elixir's concurrency edge at our
expected scale (§7). Revisit if the meta server becomes the bottleneck, and it probably won't.

---

## 3. Topology

```
                          ┌───────────────────────┐
   Godot 4 client ──HTTPS──│  Gateway / Edge        │
   (Win/Mac/Linux)         │  (Fly app, ≥2 regions) │
        │                  │  auth, session, routing│
        │                  └───────┬───────────────┘
        │                          │ 6PN private net
        │            ┌─────────────┼──────────────┬────────────────┐
        │            ▼             ▼              ▼                ▼
        │     ┌────────────┐ ┌──────────┐  ┌────────────┐  ┌────────────┐
        │     │ World svc  │ │ Yard svc │  │ Market svc │  │ Tick svc   │
        │     │ hexes,     │ │ designs, │  │ trade,     │  │ scheduler, │
        │     │ movement,  │ │ builds,  │  │ contracts, │  │ convoys,   │
        │     │ pressure   │ │ refits   │  │ prices     │  │ colonies   │
        │     └─────┬──────┘ └────┬─────┘  └─────┬──────┘  └─────┬──────┘
        │           └─────────────┴──────┬───────┴───────────────┘
        │                                ▼
        │                     ┌─────────────────────┐
        │                     │ Postgres (primary)  │
        │                     │ + read replicas     │
        │                     └─────────────────────┘
        │                                ▲
        │                                │ results write-back
        │   WebSocket    ┌───────────────┴────────────────┐
        └────────────────│  Battle Instances              │
          (per battle)   │  headless Godot, 1 Machine each │
                         │  ephemeral, start-on-demand     │
                         └─────────────────────────────────┘
```

### Why this shape
- The **meta services** are stateless HTTP + Postgres. Boring, cheap, easy to scale, easy to
  reason about. Deploy as one Fly app per service (or one app with internal routing early on;
  don't split prematurely).
- The **battle instances** are the only realtime component, and they are *perfectly*
  ephemeral: created on contact, destroyed on result write-back. This is exactly what
  Fly Machines' API-driven start/stop is built for.
- **Fly's private networking (6PN, `.internal` DNS)** means services talk to each other
  without public exposure. Only the gateway and battle instances need public ingress.

---

## 4. Battle Instances: the interesting part

### Lifecycle
```
 World svc detects contact in hex
      ↓
 Build a BattleManifest (JSON):
   participants, ship designs (fully resolved), crew/officer stats,
   terrain, installations, objectives, scenario type
      ↓
 Call Fly Machines API: create/start a Machine from the
 headless-combat-server image, in the region nearest the participants
      ↓
 Machine boots, loads manifest, opens a WebSocket listener,
 registers itself with World svc, returns its address
      ↓
 Clients connect directly to that Machine's address with a signed join token
      ↓
 Battle runs (10-30 min) at 15 Hz authoritative tick
      ↓
 Result posted to World svc (signed, idempotent, retried)
      ↓
 Machine stops and is destroyed
```

**Key properties:**
- **One Machine per battle** gives complete blast-radius isolation. A crashed battle can't
  touch anything else, and a hung one can be killed by TTL without consequence.
- Fly Machines boot in **single-digit seconds** from a warm image, well within the 60-90s
  reinforcement window ([04](04-galaxy-and-territory.md) §3), which conveniently *is* the
  boot budget. The strategic design and the infrastructure line up here by luck; keep it.
- Keep a **small warm pool** in each active region so peak contact rates never wait on boot.
- **Hard TTL** on every Machine (35 min). No battle can leak compute.

### Netcode
- **Transport: WebSocket over TLS** (`WebSocketMultiplayerPeer` in Godot 4). Not UDP.
  - Justified entirely by §1.1: at 15 Hz with 200-400ms of interpolation buffer, TCP
    head-of-line blocking is invisible in a game where ships take seconds to turn.
  - Massive operational win: works through every corporate firewall, needs no dedicated
    IPv4, no UDP handler configuration, and no NAT traversal.
  - **⚠️ Verify:** Fly.io *does* support UDP, but historically it requires a dedicated IPv4
    address and specific service handler configuration, with more caveats than TCP. Confirm
    current status before assuming UDP is a cheap fallback. **The design should not need it.**
- **Model: server-authoritative, client-side interpolation, no client prediction of other
  ships.** The client predicts only its own flagship's movement (which is smooth and
  inertial, so it predicts trivially well) and interpolates everything else.
- **Inputs are intents, not positions:** `set_heading`, `set_throttle`, `allocate_power`,
  `fire_weapon(id, target)`, `set_shield_bias`, `board(target)`. All validated server-side.
  A client can never assert a position, a hit, or a damage value.
- **Bandwidth estimate:** 24 ships × ~120 bytes of delta-compressed state × 15 Hz ≈
  **~45 KB/s down** per client at worst case, before delta/interest optimization. Trivially
  fine. There is no bandwidth problem here.
- **Determinism is not required.** Because the server is authoritative and clients only
  interpolate, we avoid the entire lockstep-determinism rabbit hole. Dry-dock simulation runs
  the same C# sim locally with no networking at all.

### Anti-cheat
- Server owns all state. Clients send intents only.
- **Fog of war is enforced server-side**: a client is never sent state for a cloaked or
  out-of-sensor-range ship. This is the one place where "just send everything and let the
  client hide it" would be fatal, so interest management is a *security* requirement, not an
  optimization.
- Sanity-check input rates and reject impossible command sequences.
- Ship designs are resolved and validated **server-side** from the database at manifest
  build time. The client's fitting screen is a convenience UI; it is never a source of truth.

---

## 5. Persistence

**Postgres** (Fly Managed Postgres, or self-managed on Fly volumes, *verify current
offering and pricing*), single logical primary with read replicas in active regions.

Rough schema domains:

| Domain | Notable tables |
|---|---|
| Accounts | `accounts`, `characters`, `faction_standing`, `rank` |
| Shipyard | `hulls`, `components`, `blueprints_owned`, `designs`, `design_revisions`, `ships`, `build_queue` |
| People | `officers`, `officer_traits`, `crew_pools`, `marine_pools` |
| Galaxy | `hexes`, `hex_pressure`, `jump_links`, `installations`, `station_modules`, `colonies`, `surveys`, `anomalies` |
| Fleet | `squadrons`, `squadron_ships`, `movement_orders` |
| Economy | `resource_stores` (location-scoped!), `trade_routes`, `convoys`, `market_orders`, `contracts`, `transactions` |
| History | `battles`, `battle_participants`, `battle_results`, `kill_log` |

**Design notes:**
- `resource_stores` is **location-scoped by design**: there is no global balance. This
  enforces [05](05-economy-and-expansion.md) §1 at the schema level, which is where it
  belongs.
- **Ships are rows, not blobs.** A ship is a hull row + fitted-component rows + assigned
  officers. Damage state persists between battles.
- `designs` are immutable per revision; ships reference the revision they were built from,
  so a design edit never retroactively changes existing hulls.
- **Battle write-back is idempotent** on `battle_id`: a retried result post must never
  double-award salvage. This is the most dangerous consistency boundary in the system and
  deserves explicit tests.

**Caching:** avoid Redis initially. Hex state is small enough to cache in-process with
short TTLs, and the galaxy changes slowly. Add Redis only when measurement demands it.

---

## 6. The Tick Service

A single scheduler app (leader-elected, one active instance) advancing world time:

| Tick | Interval | Work |
|---|---|---|
| Movement | 30 s | Advance squadrons, detect contact, fire battle creation |
| Convoy | 60 s | Advance convoys, resolve arrivals, detect interception |
| Supply | 5 min | Recompute supply propagation from stations |
| Pressure | 5 min | Decay/apply hex control pressure, evaluate flips |
| Production | 15 min | Colony output, extraction, build queues, station upkeep |
| Market | 15 min | Regional price drift toward supply/demand |
| Season | daily | Objectives, Bloom expansion, seasonal scoring |

All ticks are **idempotent and resumable** from a `world_tick` cursor, so a restart or
redeploy mid-tick cannot double-produce resources. **Write this property in from day one**.
Retrofitting it into an economy that's already live is close to impossible.

---

## 7. Scale Targets & Cost

Starting assumptions to design against (revise with real data):

| Metric | Target |
|---|---|
| Registered accounts | 50,000 |
| Peak concurrent players | 3,000 |
| Peak concurrent battles | 150 |
| Avg players per battle | 4 |
| Battle Machine | 1 shared CPU, 512 MB-1 GB |
| Meta service instances | 4-8 shared CPUs across services |
| Database | Single primary, 4-8 GB RAM, + replicas |

**Rough monthly infrastructure estimate at that scale: low four figures USD**, dominated by
battle-instance CPU-seconds and the database. **This is a rough order-of-magnitude figure,
not a quote**. Model it properly against current Fly pricing before it goes in a budget.

The economics are favorable because battle Machines only exist while battles do. At 150
concurrent battles averaging 18 minutes, that's a genuinely small amount of compute-time,
and it costs nothing at 4am.

---

## 8. Regions & Sharding (open, see GDD §11.6)

The unresolved question: one galaxy globally, or one per region?

- **Meta services are latency-tolerant** (nobody notices 200ms on a build queue), so they can
  be global with regional read replicas. Not the problem.
- **Battle instances are latency-sensitive**, but only mildly (§1.1): a 15 Hz slow-paced
  sim tolerates 150ms fine, and 250ms acceptably.
- The real problem is **cross-region battles**: a Sydney player and a Frankfurt player in one
  instance means someone gets 300ms+.

**Recommended approach:** **one galaxy per macro-region** (NA / EU / APAC), each a complete
independent shard with its own Postgres and its own map. Rationale:

- A single global galaxy makes some fleet battles unplayable for someone, always.
- A hex-based territorial war is fundamentally a *timezone-local* activity: a front only
  works if the people fighting over it are awake at the same time. Splitting by region splits
  along the grain of the design rather than against it.
- Each shard needs a healthy population; three shards at 1,000 concurrent each is a
  functioning war, and starting with **one shard** and adding regions on demand avoids
  splitting an early population.

**Launch with a single region. Add shards only when concurrency justifies it.** An empty
second shard is worse than a laggy first one.

---

## 9. Client Architecture (Godot 4)

Three largely separate front-ends sharing an asset and data layer:

| Scene tree | Responsibility |
|---|---|
| `ShipyardRoot` | Fitting UI, budget bars, arc rose, derived stats, dry-dock sim. Pure local + REST. |
| `GalaxyRoot` | Hex map, fleet orders, trade/colony/station management. REST + light WebSocket for push. |
| `BattleRoot` | The tactical sim client. WebSocket to a battle Machine. |

- **Shared:** `TheFederation.Sim` (C# class library: rules, math, validation),
  a REST client, and the asset/data catalog.
- **Hex rendering: unresolved, and blocked on a project rule.** A TileMap is unlikely to
  carry 3,000 hexes with several layered, frequently changing overlays, and the map needs
  smooth zoom from whole-galaxy down to a single hex. The obvious answer is a
  `MultiMeshInstance2D` or a shader driven mesh fed by a data texture.

  **That answer conflicts with `CLAUDE.md` §5.1, which forbids procedurally generated meshes
  and scenes.** It is therefore *not adopted*. The hex map needs an explicit decision before
  any rendering work starts, and the options are:
  1. A statically authored hex tile scene, instanced per hex, with overlays as child nodes.
     Fully rule compliant. Needs a load test at 3,000 hexes before it can be trusted.
  2. A statically authored hex *mesh file* (per §2, committed as `.obj`/`.gltf`) drawn many
     times via instancing. The geometry is authored, not generated, so only the
     *placement* is programmatic. This is the most likely reconciliation.
  3. A documented exception in `CLAUDE.md` §7 for map rendering specifically.

  Option 2 looks like the right reading of the rule: author the geometry as a file, and let
  code place instances of it. Confirm before building.
- **Dedicated server export:** the headless combat server is a **dedicated server export
  preset** of the same project, stripped of rendering, audio, and client-only scenes. Same
  repo, same sim code, no duplicated logic. This is the payoff for choosing Godot on the
  server side rather than a separate engine.

---

## 10. Deployment

- **One Fly app per service.** `tf-gateway`, `tf-world`, `tf-yard`, `tf-market`, `tf-tick`,
  `tf-battle`. Early on, collapse world/yard/market into one app and split later. Premature
  service splitting is the most common way to make a small team slow.
- `tf-battle` is **not** a normal always-on app: its Machines are created and destroyed
  programmatically via the Machines API by `tf-world`.
- **CI:** GitHub Actions → build client exports + server images → `fly deploy` per service.
  The Godot export step needs export templates in the build container; cache them.
- **Migrations** run as a release command, gated, with an explicit rollback path. Once the
  economy is live, a bad migration is the worst incident available to us.
- **Secrets** via `fly secrets`. Battle Machines receive only a short-lived scoped token.
  They must not hold database credentials. A battle instance is the most exposed component in
  the system (clients connect to it directly); it should be able to do nothing except report
  a result to `tf-world`.
- **Observability:** structured logs shipped off-platform, per-battle trace IDs, and a metrics
  dashboard whose first two panels are *battle Machine boot time* and *tick lag*. Those two
  numbers predict every scaling problem we're going to have.

---

## 11. Technical Risk Register

| Risk | Severity | Mitigation |
|---|---|---|
| Combat isn't fun; everything else is wasted | **Critical** | Vertical slice is combat-only, 2 ships, local, no netcode. Prove fun before building infrastructure ([07](07-roadmap.md) M1) |
| Fitting system too complex to be legible | High | Playtest the fitting UI in isolation with new players from M2 onward; faction presets as the on-ramp |
| Battle Machine boot latency spikes at peak | Medium | Warm pool per region; boot time is a tracked SLI |
| Economy inflation / duplication exploits | High | Idempotent ticks and idempotent battle write-back from day one; full transaction audit log; no global market |
| Fly Machines API rate limits under contact storms | Medium | **Verify limits early.** Queue battle creation, warm pool absorbs bursts |
| UDP unavailable / awkward on Fly | Low | Architecture deliberately requires only WebSocket/TCP (§4) |
| Single Postgres primary becomes the ceiling | Medium | Read replicas; region sharding (§8) is the real answer and is already the plan |
| Godot .NET export friction on some targets | Medium | Validate .NET export to all target platforms in M1, before code volume makes it expensive to reverse |
| Cross-region latency in fleet battles | Medium | Region sharding (§8); instance placed nearest participant centroid |
