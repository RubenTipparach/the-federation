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

The surface is a whorley function evaluated in the world's local space, so it is
procedural: no textures, no memory, and it turns with the world rather than
sliding across it.

---

## 2. The two changes

The unmodified original is committed beside ours as
`simple_spatial_planet.gdshader` and nothing loads it. The game runs
`planet.gdshader`, which is that file with two changes and no others. Keeping
both is what makes the diff readable and what lets the shader be updated from
upstream.

**1. The depth write is OpenGL's.** The original writes
`DEPTH = clipPos.z/clipPos.w`, which is Vulkan's 0 to 1 convention. This project
runs `gl_compatibility` (`project.godot`), where clip depth is -1 to 1, so every
fragment was rejected and a planet rendered as nothing whatsoever. Ours is
`DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;`. This was diagnosed by rendering an
unshaded control sphere in the same frame, which appeared, so the mesh and the
camera were not at fault.

**2. The surface colour is ramped.** The original writes the raw whorley noise
vector straight to `ALBEDO` and has **no colour input of any kind**. Every world
it draws is therefore the same red and cyan marble whatever it is meant to be,
and varying the only two things it exposes, the rim colour and the distortion,
does not change that. Ours turns the noise into a height and ramps the height
through three colours. That is the entire difference between a terran world and
an ice world here.

Everything else, including the ray-sphere intersection and the whorley function
that gives the bands their shape, is the author's.

---

## 3. The colours are ours, but not every pixel is

`data/palette.json` `worlds` gives each variant four palette roles: `low`, `mid`
and `high` for the surface ramp, and `rim` for the limb. `data/tuning.json`
`terrain_view.planets` gives each variant its shape: how far the bands are
warped, where low ground gives way to middle ground, how many bands wrap around
and across, the atmosphere at the limb, and how fast it turns.

**The shader blends between those colours**, so a world is not made only of
palette entries the way the ships and the panels are. That is a real departure
from CLAUDE.md 3.1 and it is listed as an exception in section 7 of that file,
agreed on 2026-08-09. What the palette still decides is which four colours a
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
