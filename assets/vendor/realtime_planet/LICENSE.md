# Realtime Planet Shader

The worlds in the tactical view are drawn by a Godot port of the procedural
planet shader from **realtime-planet-shader**.

- **Source:** https://github.com/jsulpis/realtime-planet-shader
- **Also published as:** https://www.shadertoy.com/view/Ds3XRl
- **Author:** Julien Sulpis
- **Licence:** GPL-3.0

**This licence is why The Federation is GPL-3.0.** The GPL is copyleft: a work
that includes GPL code is GPL, and the full text is at `LICENSE` in the root of
this repository. That was a deliberate choice rather than an oversight, and
`docs/14-reference-planet-shader.md` records when and why it was made. Anything
vendored here in future must be compatible with it.

| File | What it is |
|---|---|
| `procedural.fragment.glsl` | The author's original, unmodified. Nothing loads it. |
| `planet.gdshader` | The surface, ported to a Godot spatial shader. |
| `atmosphere.gdshader` | The author's limb glow, on its own shell mesh. |

Both ported files carry a header listing what is the author's and what is ours.
The original is kept beside them for the same reason it always is: it is what
makes the diff readable and what lets the port be checked against upstream.
