# Simple Spatial Planet

The shader the tactical view draws worlds with.

- **Source:** https://godotshaders.com/shader/simple-spatial-planet/
- **Author:** Nolkaloid
- **Licence:** CC0. The page states the shader is released under CC0 and may be
  used freely without the author's permission.

Only the shader code is covered by that grant. The page's images and videos are
not, and none are copied here.

| File | What it is |
|---|---|
| `simple_spatial_planet.gdshader` | The original, unmodified. Nothing loads it. |
| `planet.gdshader` | Ours: the original with two changes, and what the game runs. |

The two changes are listed at the top of `planet.gdshader` with the reason for
each: an OpenGL depth write, because this project runs the Compatibility
renderer and the original writes Vulkan's convention, and a colour ramp,
because the original has no colour input at all and draws every world the same.
Keeping the untouched original beside it is what makes that diff readable and
what lets the shader be updated from upstream.

See `docs/14-reference-planet-shader.md`.
