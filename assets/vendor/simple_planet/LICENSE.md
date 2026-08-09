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
| `planet.gdshader` | What the game runs: the author's sphere, our ground. |

`planet.gdshader` keeps the author's ray sphere intersection, depth write,
fresnel rim and whorley band function, and replaces what those were painted
with. The changes are listed at the top of that file with the reason for each.
The short version: the depth write is OpenGL's, because this project runs the
Compatibility renderer and the original writes Vulkan's convention, and the
surface is a warped fractal noise with a sea, a coastline, polar caps and an
optional lava glow, because the author's whorley function is a flow field that
draws belts and therefore draws a gas giant whatever colours it is given.

Keeping the untouched original beside it is what makes that diff readable and
what lets the sphere half be updated from upstream.

See `docs/14-reference-planet-shader.md`.
