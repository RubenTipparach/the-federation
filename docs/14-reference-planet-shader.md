# 14. Reference: the planet shader

The worlds in the tactical view are drawn by **Simple Spatial Planet**, by
Nolkaloid.

- **Source:** https://godotshaders.com/shader/simple-spatial-planet/
- **Licence:** CC0. The page states the shader may be used freely without the
  author's permission. Only the code is covered; the page's images are not, and
  none are copied here.
- **Vendored at:** `assets/vendor/simple_planet/`, with the licence beside it.

This is not a design we are learning from and reimplementing, the way
[09-reference-federation-commander.md](09-reference-federation-commander.md) is.
It is code we run, under a licence that permits it, and this document exists so
that is written down somewhere other than a licence file.

What each world is meant to be, and what it does to a ship, is
[15-worlds.md](15-worlds.md). This document is the provenance and the mechanism.

---

## 1. How it works, and why that matters here

**It ignores the mesh it is drawn on.** The shader intersects a sphere
analytically in the fragment stage: for every fragment it fires a ray from the
camera, solves the ray-sphere quadratic, and shades the point it hits, writing
its own `DEPTH` from that point rather than from the triangle. The mesh exists
only to get fragments generated in the right part of the screen.

Three consequences, all of them useful:

1. **The limb is a true circle at any zoom.** It is not a polygon silhouette, so
   a world does not go faceted when the camera closes in.
2. **The mesh needs no texture coordinates.** That matters concretely:
   `assets/meshes/sphere.obj` has none. Every face in it is `f v//vn` and the
   file contains zero `vt` lines. A shader that sampled textures at `UV` would
   read one texel across the whole world, which is a mistake worth knowing about
   before the next planet shader is tried.
3. **The mesh must contain the sphere.** Fragments are only generated where the
   mesh covers, so `scenes/terrain/planet.tscn` scales it past the world it
   holds. `terrain_view.mesh_slack` in `data/tuning.json` is that margin.

The surface is evaluated in the world's local space, so it is procedural: no
textures, no memory, and it turns with the world rather than sliding across it.

---

## 2. What is the author's, and what is ours

The unmodified original is committed beside ours as
`simple_spatial_planet.gdshader` and nothing loads it. The game runs
`planet.gdshader`. Keeping both is what makes the diff readable and what lets
the sphere half be updated from upstream.

**The author's:** the ray-sphere intersection, the depth write, the fresnel rim,
and the whorley band function.

**Ours, and why each one had to be:**

**1. An OpenGL depth write.** The original writes `DEPTH = clipPos.z/clipPos.w`,
which is Vulkan's 0 to 1 convention. This project runs `gl_compatibility`
(`project.godot`), where clip depth is -1 to 1, so every fragment was rejected
and a planet rendered as nothing whatsoever. Diagnosed by rendering an unshaded
control sphere in the same frame, which appeared, so the mesh and the camera
were not at fault.

**2. A ground height field.** This is the one that matters. The author's whorley
function is a flow field: it produces horizontal belts, so **every world it
draws is a gas giant** whatever colours it is handed. No amount of tuning
changes that, because the banding is the function. Ours is a fractal gradient
noise evaluated on the sphere's own direction vector with a domain warp, which
produces continents. A `bands` uniform mixes between the two, so a gas giant
asks for the author's and every rocky world asks for ours.

The direction fed to that noise is **normalized**, which the original did not
need. It passed `dir` only to `uvOnSphere`, two atans that do not care about
length. `inverse(MODEL_MATRIX)` undoes the mesh's scale as well as its rotation,
and that mesh is scaled to the world's radius, so what arrives is about a
sixtieth of a unit long. Read a noise field at that scale and every fragment
lands in the same cell, which draws a plain ball. That was the first thing this
change got wrong.

**3. A sea with a coastline.** Height below `seaLevel` is water, above it is
ground, and the boundary is a narrow band rather than a gradient. A shoreline is
the single feature that tells a player at a glance that a world has oceans.

**4. Polar caps.** Ice is a function of latitude rather than of height, with the
ground noise roughening its edge so it is not a circle drawn on with a compass.

**5. A lava glow.** Where a world's palette names a `glow` colour, the lowest
ground emits, so a volcanic world lights its own fissures on the night side.

The noise is four octaves of gradient noise with a single-octave domain warp.
Five octaves is visibly better on a still image and costs a fifth more per
fragment over a body that can fill a quarter of the screen, which is the wrong
trade for a game that has to run in a browser.

---

## 3. The colours are ours, but not every pixel is

`data/palette.json` `worlds` gives each variant eight palette roles: `abyss`,
`sea`, `shore`, `land` and `peak` for the surface ramp, `cap` for the ice, `rim`
for the limb, and `glow` for emissive ground. An empty name means the world has
none of that thing. `data/tuning.json` `terrain_view.planets` gives each variant
its shape: continent size, warp, sea level, coastline hardness, cap latitude,
glow depth, the belt controls for the one world that uses them, the limb, and
the spin.

**The shader blends between those colours**, so a world is not made only of
palette entries the way the ships and the panels are. That is a real departure
from CLAUDE.md 3.1 and it is listed as an exception in section 7 of that file,
agreed on 2026-08-09. What the palette still decides is which colours a
world is built from; what it no longer decides is every pixel.

---

## 4. What was here before

Until 2026-08-09 the worlds were drawn by **Deep-Fold's PixelPlanets** (MIT),
four 2D shaders rendered into small viewports and shown on billboarded sprites.
Those shaders never blended, so every pixel was a palette entry and section 3.1
held exactly. They were replaced because a billboard cannot rotate, cannot
compress its surface toward the limb, and cannot take a terminator from the
scene's own light, and because the pixel art look was not wanted for worlds.

The vendored directory and the four scenes that wrapped it were removed rather
than left in place, because two planet renderers is the divergence CLAUDE.md 4.1
exists to prevent. The history is in git if any of it is wanted back.

Three other shaders were tried in the same pass and rejected, which is recorded
here so the ground is not covered twice:

| Shader | Why not |
|---|---|
| [Godot Planet Shader](https://godotshaders.com/shader/godot-planet-shader/) | Never writes `ALBEDO`, and its `ALPHA` is a fresnel, so the sphere fades out at the limb instead of ending. Wants seven authored maps. |
| [3D Pixelated Planet](https://godotshaders.com/shader/3d-pixelated-planet/) | Good, and genuinely rotates, but it is pixel art by construction and multiplies its colours rather than looking them up. |
| [Zylann's atmosphere](https://github.com/Zylann/godot_atmosphere_shader) | Forward+ only. Renders nothing on the Compatibility renderer. |
