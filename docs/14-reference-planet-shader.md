# 14. Reference: the planet shader

The worlds in the tactical view are drawn by a Godot port of the procedural
planet shader from **realtime-planet-shader**, by Julien Sulpis.

- **Source:** https://github.com/jsulpis/realtime-planet-shader
- **Also published as:** https://www.shadertoy.com/view/Ds3XRl
- **Licence:** GPL-3.0
- **Vendored at:** `assets/vendor/realtime_planet/`, with the author's original
  beside the port.

---

## 1. This is why the game is GPL-3.0

Everything else vendored here has been permissive: MIT or CC0. This is not. The
GPL is copyleft, so a work that includes GPL code is itself GPL, and that
reaches the whole game rather than the one file. Adopting it was a deliberate
decision taken on 2026-08-09 with that consequence stated first, and the full
licence text is committed at `LICENSE` in the root of this repository.

What it means in practice, in plain terms:

- Anyone we distribute a build to may ask for the source of that build, and we
  have to give it to them under the same licence. That includes the itch.io
  builds.
- Anything vendored in future has to be GPL compatible. MIT, BSD and CC0 all
  are. A proprietary or non commercial asset licence is not.
- It does not stop us selling the game, and it does not reach assets that are
  merely data rather than part of the program.

If that ever becomes unwanted, the way out is to replace this shader, not to
quietly relicense: the obligation came in with the file and leaves with it.

---

## 2. How it works

**It ignores the mesh it is drawn on.** For every fragment it fires a ray from
the camera and intersects a sphere analytically, then shades the point it hits
and writes its own `DEPTH` from that point rather than from the triangle. The
mesh exists only to get fragments generated in the right part of the screen.

**The sphere has terrain in its radius.** The intersection is run twice: once
against the smooth sphere to find roughly where the ray lands, then again
against a sphere whose radius is the smooth one plus a fractal noise sampled at
that point. That is what gives a world mountains that break its silhouette
rather than a perfect circle with a picture on it.

Three consequences worth knowing:

1. **The limb is a true circle at any zoom**, so a world does not go faceted
   when the camera closes in.
2. **The mesh needs no texture coordinates**, which matters because
   `assets/meshes/sphere.obj` has none: every face is `f v//vn` and there are
   zero `vt` lines in the file.
3. **The mesh must contain the displaced sphere**, terrain and all, or the
   fragments near a mountain are never generated.
   `terrain_view.mesh_slack` is that margin.

**The noise is a texture, not arithmetic.** A 3D noise texture authored in
`scenes/terrain/planet.tscn` is sampled rather than computed, which is the
single biggest reason this runs at a sensible speed: the field is read six
times per fragment for the terrain, twice more for its slope, and several times
again for clouds.

---

## 3. What is the author's and what is ours

The author's original is committed unmodified as `procedural.fragment.glsl` and
nothing loads it. Both ported files carry a header listing the split; the short
version:

**His:** the displaced ray sphere intersection, the fbm and the domain warped
fbm, flattening the noise under the oceans so a sea bed is not corrugated, the
altitude ramp with its levels and transitions, the cloud layer thinned over
high ground, specular on water only, the softened terminator, and the stack of
four powers that makes the atmosphere read as air rather than as an outline.

**Ours:**

1. **It is a spatial shader in a scene.** He renders one planet over a whole
   frame from a fixed camera. This runs on a mesh at a real position and radius,
   takes its ray from our camera, and writes depth, so ships sort against it.
2. **It works in unit planet space.** Every level he wrote assumes a radius of
   about 1, and our worlds are 40 to 55 arena units across, so the ray is
   divided by the planet's radius before the intersection and multiplied back
   after. That is what lets his numbers stay his numbers.
3. **The colours are palette roles**, fed from `data/palette.json`.
4. **The gas giant keeps its belts.** Our whorley band field survived the
   replacement, because a gas giant has no coastline to draw.
5. **No stars, no moon, no tone mapping, no vignette.** We have a sky shader,
   the simulation places real moons, and tone mapping one object would leave it
   in a different colour space from the rest of the frame.
6. **The atmosphere is a separate pass** on its own shell mesh, drawn additively
   with no depth write, so the haze can reach past the limb over the stars while
   the body keeps its depth.
7. **A night side**, so a world whose palette names a `glow` keeps it on the
   unlit half.
8. **The normal is built differently.** He differences the ray sphere
   intersection itself, three more traces around the hit. Ported into unit
   planet space that comes out inverted, which lights every world from behind
   and draws a black disc; it cost a render to find. Ours differences the height
   one step earlier, along two tangents, and bends the outward normal by that
   slope. Same terrain, same light, and the direction cannot be wrong because it
   starts from the normal.

**Calibration was the other trap.** His fbm ends in `pow(total, 5)`, which
crushes a mean of 0.5 to about 0.03. At the noise strength that looked
reasonable the tallest ground on a world reached exactly the sand line, so every
world rendered as unbroken ocean. The strengths in `data/tuning.json` are set
against the levels, not guessed, and moving one means checking the other.

---

## 4. The colours are ours, but not every pixel is

`data/palette.json` `worlds` gives each variant nine palette roles: `abyss`,
`sea`, `shore`, `land` and `peak` for the altitude ramp, `cap` for the highest
ground, `cloud` for the weather, `rim` for the atmosphere and `glow` for the
night side. An empty name means the world has none of that thing.
`data/tuning.json` `terrain_view.planets` holds the shape.

**The shader blends between those colours**, so a world is not made only of
palette entries the way the ships and the panels are. That is a documented
exception in CLAUDE.md section 7. What the palette still decides is which
colours a world is built from; what it no longer decides is every pixel.

---

## 5. What was here before

Two shaders preceded this one, both replaced rather than kept beside it, because
two planet renderers is the divergence CLAUDE.md 4.1 exists to prevent.

| Shader | Licence | Why it went |
|---|---|---|
| Deep-Fold PixelPlanets | MIT | 2D billboards. Could not rotate, could not compress toward the limb, and the pixel art look was not wanted for worlds. |
| Simple Spatial Planet, by Nolkaloid | CC0 | A real ray traced sphere, and the base this one improves on. Its whorley surface drew belts and nothing else, so every world was a gas giant until we bolted our own continents onto it. Its band field is the one part still in use. |

Two others were tried and rejected in the same pass: the Godot Planet Shader
(never writes `ALBEDO`, and its fresnel `ALPHA` fades the limb out instead of
ending it) and 3D Pixelated Planet (good, and genuinely pixel art by
construction). Zylann's atmosphere addon is Forward+ only and renders nothing on
the Compatibility renderer.
