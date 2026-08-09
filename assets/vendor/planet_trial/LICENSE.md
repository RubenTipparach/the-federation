# Trial planet shaders

Two CC0 shaders from godotshaders.com, vendored ONLY to be tried in the
tactical view and photographed. Nothing in the game loads them: they are
placed at runtime by a scratch harness. If one is adopted it moves out of
`planet_trial/` into its own documented vendor directory with a `docs/`
reference file, the way `assets/vendor/pixel_planets/` is (CLAUDE.md 10).

| File | Source | Licence |
|---|---|---|
| `simple_spatial_planet.gdshader` | https://godotshaders.com/shader/simple-spatial-planet/ | CC0 |
| `godot_planet_shader.gdshader` | https://godotshaders.com/shader/godot-planet-shader/ | CC0 |

Both pages state the shader code is released under CC0 and may be used
freely without the author's permission. Neither page's images or videos are
covered by that grant, and none are copied here.

`simple_spatial_planet_glfix.gdshader` is our copy of the first shader with
exactly one line changed. The original writes `DEPTH = clipPos.z/clipPos.w`,
which is the Vulkan depth convention; under this project's `gl_compatibility`
renderer the range is -1 to 1, so every fragment was rejected and the sphere
rendered as nothing at all. The fixed line is
`DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;`. The unmodified original is kept
beside it so the difference stays one readable diff.
