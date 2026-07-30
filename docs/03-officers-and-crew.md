# 03. Officers & Crew

Ships don't fight. Crews fight. This system exists to make a hull you've flown for a month
feel different from an identical hull off the slip.

---

## 1. Bridge Officers

Each ship has **6 officer posts**. Officers are named, persistent, individually developed
NPCs that the player recruits, trains, and can lose.

| Post | Governs |
|---|---|
| **Helm** | Turn rate bonus, evasion, collision avoidance, terrain handling |
| **Gunnery** | Accuracy, capacitor charge rate, overload safety margin |
| **Engineering** | Power reallocation ramp speed, damage-control efficiency, reactor stability |
| **Tactical** | Sensor/lock quality, ECM/ECCM effectiveness, seeking-weapon guidance |
| **Science** | Anomaly/exploration outcomes, cloak detection, research contribution |
| **Marine CO** | Boarding attack strength, boarding defense, hit-and-run success |

### Officer attributes
Each officer has a **rating (1-100)** in their specialty plus:

- **Traits** (1-3): qualitative modifiers, not just numbers:
  `Cool Under Fire` (no penalty while hull critical) · `Reckless` (+overload damage,
  +reactor damage risk) · `Nebula-Born` (ignores nebula sensor penalty) ·
  `Boarder` (+marine morale) · `Meticulous` (faster damage control, slower reload) ·
  `Loyal` (won't defect; survives capture) · `Green` (rating grows faster).
- **Fatigue**: accumulates over consecutive deployments; degrades performance until the
  officer gets shore leave. This is the mechanism that makes deep raiding expensive and
  gives players a reason to rotate personnel rather than fielding one god-crew forever.
- **Experience**: grows through use, faster in the situations they were actually tested in.
  A gunnery officer who fights a lot of close brawls develops differently from one who
  spends a year on long-range escort duty.

### Officers on consorts matter mechanically
Consort ships are AI-flown, and **their AI competence is their officers' ratings** (see
[01-tactical-combat.md](01-tactical-combat.md) §9). A consort with a 20-rated tactical
officer flies into plasma; an 80-rated one manages its own shield rotation and power
allocation well. This makes officer investment across the whole squadron a real strategic
spend rather than a stat tax on the flagship only.

### Recruitment
- **Academy** (faction station): reliable, mid-rated, costs credits + time.
- **Contracts**: high-rated specialists on the open market; expensive, sometimes disloyal.
- **Promotion from crew**: a long-service crew complement produces officer candidates.
  Slow, cheap, produces `Loyal` officers. The sentimental path, and mechanically good.
- **Captured officers**: enemy officers taken in a boarding action can, occasionally, be
  turned. Rare, flavorful, and a great reason to board rather than destroy.

---

## 2. Crew

Crew is a **pool with a quality level**, not individuals.

| Property | Effect |
|---|---|
| **Count** | Must meet the design's crew requirement (see 02 §3) or the ship is undermanned |
| **Quality** (Green / Regular / Veteran / Elite) | Multiplies reload rate, damage control, boarding defense, and system efficiency |
| **Morale** | Rises with victories, falls with losses/casualties/unsupplied deployment. Low morale can cause failure-to-fire and surrender-under-boarding |

- Quality improves through **survived combat** and through **paid training** at a station.
  Training is the fast path; survival is the cheap path.
- Crew casualties come from internal hits (crew quarters), boarding defense, and hull
  breaches. Replacements are Green, so a badly mauled Elite crew is **diluted**: a real
  and painful loss even when the ship survives. This is one of the best sources of
  "that fight cost me" feeling in the design.

---

## 3. Marines

Marines are a separate, expensive complement housed in barracks (which cost berths).

- **Count** limited by fitted marine barracks.
- **Equipment tier** purchased separately; scales boarding strength.
- Used for: **boarding** (capture), **boarding defense**, **hit-and-run raids**, and
  **planetary assault** on the strategic layer.
- Marines lost in a failed boarding are **gone** and must be re-purchased and re-trained
  at a station. Boarding is a resource commitment, not a free action.

Fitting marines is the clearest example of the four-budget tension: barracks cost space,
marines cost berths that weapon crews needed, and the whole package does nothing at all in
a fight you can't get close in.

---

## 4. Loss, Injury, Permadeath

Per GDD §11.4, the default position:

| Event | Officer outcome |
|---|---|
| Ship survives, bridge hit | **Injured**: out of action for a recovery period, may gain a scar trait |
| Ship crippled, withdrawn | Officers survive |
| Ship destroyed, pods recovered | Officers survive, heavy fatigue, crew mostly lost |
| Ship destroyed, pods denied/not recovered | **Permanent loss** of officers aboard |
| Ship captured | Officers become the captor's prisoners; ransom, exchange, or recruitment |

This makes **escape pod recovery** a live objective in the closing moments of a losing
fight, and gives a winning player a genuine choice: hunt the pods for a permanent kill on a
rival's veteran crew, or let them go and take the salvage instead.

Officers are never *unrecoverably* central. Losing your best engineer hurts for a few
weeks, not forever. Pillar P4 holds.

---

## 5. Progression Shape

```
   new player: Green crew, Regular officers, faction preset design
        ↓  (fights, survives, trains)
   competent: Veteran crew, specialized officers with useful traits
        ↓  (deep specialization, recruited specialists, promoted loyalists)
   veteran: Elite crews on multiple hulls, a bench of officers to rotate against fatigue,
            and captured foreign blueprints to build from
```

Note what this progression *isn't*: raw combat power inflation. An Elite crew is roughly
**15-25% more effective** than Green: decisive between equals, not insurmountable. The
veteran's real advantage is **depth of bench**: they can field six well-crewed ships and
rotate them, where a new player can field one.
