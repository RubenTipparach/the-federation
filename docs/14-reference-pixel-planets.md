# 14. Reference: Deep-Fold's PixelPlanets

The worlds in the tactical view are drawn by shaders from **PixelPlanets** by
Deep-Fold.

- **Source:** https://github.com/Deep-Fold/PixelPlanets
- **Licence:** MIT, copyright (c) 2020 Deep-Fold. The full text is committed at
  `assets/vendor/pixel_planets/LICENSE`.
- **Live version of the generator:** https://deep-fold.itch.io/pixel-planet-generator

What each world is meant to be, and what it does to a ship, is
[15-worlds.md](15-worlds.md). This document is only the provenance.

Unlike the Federation Commander notes in
[09-reference-federation-commander.md](09-reference-federation-commander.md), this is
not a design we are learning from and reimplementing. It is code we are using, under a
licence that permits it, and this document exists so that is written down somewhere
other than a licence file.

---

## 1. What is vendored, and what was changed

Everything under `assets/vendor/pixel_planets/` came from that repository. Four of its
planet types are here, plus the base `Planet.gd` and `Planet.tscn` they all extend:

| Directory | Their type | Our variant |
|---|---|---|
| `LandMasses/` | Land masses | `terran` |
| `IceWorld/` | Ice world | `ice` |
| `NoAtmosphere/` | No atmosphere | `barren` |
| `GasPlanetLayers/` | Gas planet with layers and a ring | `gas` |

Three changes were made, all mechanical:

1. **Resource paths repointed** from `res://Planets/...` to
   `res://assets/vendor/pixel_planets/...`, because they live somewhere else here.
2. **`Planet.tscn` converted** from their Godot 3 era scene format to format 3.
3. **A four line header added** to every file, naming the source and the licence.

Nothing else was touched. The shaders, the layer composition, and the scripts' public
API are theirs. That is deliberate: a vendored dependency that has been quietly
rewritten cannot be updated from upstream, and the diff against their repository should
stay readable.

---

## 2. How they are used

Their shaders are `canvas_item`, meaning 2D. Our battle view is 3D. Each world is
therefore rendered into its own small `SubViewport` and shown on a `Sprite3D` that
faces the camera.

**A billboard is not an approximation of a sphere here, it is the shape of one.** A
sphere projects to a circle from every direction, so a card that always faces the
camera is exactly what a sphere looks like from the tactical camera at any angle it is
allowed to take. What it buys, which a shaded 3D ball did not, is that a planet is now
made of the same chunky pixels as the ships, the icons and the panels.

The gravity well ring is not part of that card. It lies flat on the combat plane,
because unlike the planet a well genuinely is flat.

Sizes come from the simulation as they do for every other feature: one art pixel is
`body_radius * 2 / 100` sim units, so the body ends up exactly the radius
`src/sim/terrain.gd` gave it. The gas giant's viewport is three times as wide as the
others because its ring is three times as wide as its body, which is their scene's
decision and not ours to second guess.

---

## 3. The colours are ours

This is the part that matters for CLAUDE.md 3.1.

Their shaders take an array of colours and **never blend between them**. Look at
`LandMasses/PlanetUnder.gdshader`: it picks `colors[0]`, `colors[1]` or `colors[2]`
by distance from the light, and dithers along the boundary by alternating between two
of them per pixel. There is no `mix()` in the colour path at all.

So if the array is palette entries, every pixel is a palette entry. That is exactly the
guarantee section 3.1 asks for, and it is why these shaders fit a project with a strict
palette when a smoothly shaded planet did not.

The lists live in `data/palette.json` under `worlds`, one ordered list per variant,
named by colour rather than by hex. Which slice of the list goes to which layer is the
vendored script's business, documented by its own `set_colors`. Swapping the palette
stays a one file change.

`src/ui/pixel_planet.gd` resolves the list and hands it over. A variant with no list is
a hard failure rather than a fallback, because falling back would paint a world in
Deep-Fold's default colours, and those are a different palette.

---

## 4. What is not used

Their repository also contains a star, a black hole, a galaxy, an asteroid field, a
lava world, a dry terran world, a moon, and a GUI for browsing them. None of that is
vendored. If we want their asteroids later, the same three mechanical changes apply and
the same palette rule holds.
