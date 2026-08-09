# Trial planet shaders

Three CC0 shaders from godotshaders.com, vendored ONLY to be tried in the
tactical view and photographed. Nothing in the game loads them: they are
placed at runtime by a scratch harness. If one is adopted it moves out of
`planet_trial/` into its own documented vendor directory with a `docs/`
reference file, the way `assets/vendor/pixel_planets/` is (CLAUDE.md 10).

| File | Source | Licence |
|---|---|---|
| `simple_spatial_planet.gdshader` | https://godotshaders.com/shader/simple-spatial-planet/ | CC0 |
| `godot_planet_shader.gdshader` | https://godotshaders.com/shader/godot-planet-shader/ | CC0 |
| `pixel_planet_3d.gdshader` | https://godotshaders.com/shader/3d-pixelated-planet/, by Max Beier | CC0 |

Every page states the shader code is released under CC0 and may be used
freely without the author's permission. No page's images or videos are
covered by that grant, and none are copied here.

`simple_spatial_planet_glfix.gdshader` is our copy of the first shader with
exactly one line changed. The original writes `DEPTH = clipPos.z/clipPos.w`,
which is the Vulkan depth convention; under this project's `gl_compatibility`
renderer the range is -1 to 1, so every fragment was rejected and the sphere
rendered as nothing at all. The fixed line is
`DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;`. The unmodified original is kept
beside it so the difference stays one readable diff.

`pixel_planet_3d_palette.gdshader` is our copy of the third shader with five
changes, each one listed at the top of that file with the rule that forced it.
The short version: it looks its colour up in a palette table instead of
multiplying one by a light value, its limb is a hard pixel edge instead of an
antialiased one, its light bands are explicit and dithered at art pixel
resolution, and its sun is fixed in screen space rather than turning with the
globe. The first three are CLAUDE.md 3.1; the last is the convention
`src/ui/pixel_planet.gd` already follows. The unmodified original is kept
beside it.

`simple_spatial_planet_tint.gdshader` is the GL fixed copy of the first shader
with one further change: the whorley noise becomes a height and the height
picks a colour from a three colour ramp, instead of the raw noise vector being
written to ALBEDO as a colour. The published shader has no colour input at all,
so every world it draws comes out the same red and cyan marble whatever it is
meant to be. Everything else in it, including the ray sphere intersection that
gives it a real limb, is the author's.
