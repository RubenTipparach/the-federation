#!/usr/bin/env python3
# Textured preview renders for committed ship meshes.
#
# A developer tool, not part of the build: it needs Pillow and numpy, which CI
# does not have and does not require. It exists so a hull and its maps can be
# judged as pixels on screen, lit and emissive, without opening the engine.
#
# It is a small software rasterizer: perspective camera, z-buffer, perspective
# correct UVs, nearest neighbour texture sampling so pixel art stays pixel art,
# two-light lambert shading, and the emissive map added unlit on top, which is
# exactly what the engine material does with the same two textures.
#
# Usage:
#   python3 tools/render_preview.py assets/meshes/hull_frigate.obj \
#       assets/textures/hull_frigate_diffuse.png \
#       assets/textures/hull_frigate_lights.png out_dir

import math
import os
import sys

import numpy as np
from PIL import Image


def load_obj(path):
    vs, vts, vns, faces = [], [], [], []
    for line in open(path):
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            vs.append([float(parts[1]), float(parts[2]), float(parts[3])])
        elif parts[0] == "vt":
            vts.append([float(parts[1]), float(parts[2])])
        elif parts[0] == "vn":
            vns.append([float(parts[1]), float(parts[2]), float(parts[3])])
        elif parts[0] == "f":
            face = []
            for token in parts[1:]:
                ids = token.split("/")
                vi = int(ids[0]) - 1
                ti = int(ids[1]) - 1 if len(ids) > 1 and ids[1] else 0
                ni = int(ids[2]) - 1 if len(ids) > 2 and ids[2] else 0
                face.append((vi, ti, ni))
            faces.append(face)
    return (np.array(vs, dtype=np.float64), np.array(vts, dtype=np.float64),
            np.array(vns, dtype=np.float64), faces)


def look_at(eye, target, up):
    f = target - eye
    f = f / np.linalg.norm(f)
    r = np.cross(f, up)
    r = r / np.linalg.norm(r)
    u = np.cross(r, f)
    return r, u, f


class Renderer:
    def __init__(self, width, height, ss=2):
        self.w = width * ss
        self.h = height * ss
        self.out_w = width
        self.out_h = height
        self.ss = ss
        self.color = np.zeros((self.h, self.w, 3), dtype=np.float64)
        self.glow = np.zeros((self.h, self.w, 3), dtype=np.float64)
        self.depth = np.full((self.h, self.w), np.inf, dtype=np.float64)

    def background(self, top=(13, 17, 24), bottom=(5, 7, 10)):
        t = np.linspace(0.0, 1.0, self.h)[:, None, None]
        self.color = (np.array(top) * (1 - t) + np.array(bottom) * t) * np.ones(
            (self.h, self.w, 3))

    def render(self, mesh, diffuse, emissive, eye, target, fov_deg=32.0,
               lights=None, ambient=0.34, emissive_gain=1.4, diffuse_gain=1.0):
        vs, vts, vns, faces = mesh
        eye = np.array(eye, dtype=np.float64)
        target = np.array(target, dtype=np.float64)
        r, u, f = look_at(eye, target, np.array([0.0, 1.0, 0.0]))
        if lights is None:
            lights = [((0.45, 0.8, 0.35), 0.95), ((-0.6, 0.25, -0.7), 0.35)]
        lights = [(np.array(d) / np.linalg.norm(d), e) for d, e in lights]

        focal = (self.h / 2.0) / math.tan(math.radians(fov_deg) / 2.0)
        th, tw = diffuse.shape[:2]

        for face in faces:
            idx = [face[0], face[1], face[2]]
            world = np.array([vs[i[0]] for i in idx])
            uv = np.array([vts[i[1]] for i in idx])
            normal = vns[idx[0][2]]

            cam = np.array([[np.dot(p - eye, r), np.dot(p - eye, u),
                             np.dot(p - eye, f)] for p in world])
            if np.any(cam[:, 2] < 0.05):
                continue
            sx = self.w / 2.0 + cam[:, 0] / cam[:, 2] * focal
            sy = self.h / 2.0 - cam[:, 1] / cam[:, 2] * focal
            inv_z = 1.0 / cam[:, 2]

            # No backface cull: the z-buffer resolves occlusion, and OBJ slabs
            # authored by different tools disagree about winding. Degenerate
            # triangles are skipped.
            area = (sx[1] - sx[0]) * (sy[2] - sy[0]) - (sy[1] - sy[0]) * (sx[2] - sx[0])
            if abs(area) < 1e-9:
                continue

            min_x = max(int(np.floor(sx.min())), 0)
            max_x = min(int(np.ceil(sx.max())), self.w - 1)
            min_y = max(int(np.floor(sy.min())), 0)
            max_y = min(int(np.ceil(sy.max())), self.h - 1)
            if min_x > max_x or min_y > max_y:
                continue

            xs = np.arange(min_x, max_x + 1) + 0.5
            ys = np.arange(min_y, max_y + 1) + 0.5
            gx, gy = np.meshgrid(xs, ys)

            def edge(ax, ay, bx, by):
                return (gx - ax) * (by - ay) - (gy - ay) * (bx - ax)

            w0 = edge(sx[1], sy[1], sx[2], sy[2])
            w1 = edge(sx[2], sy[2], sx[0], sy[0])
            w2 = edge(sx[0], sy[0], sx[1], sy[1])
            mask = ((w0 <= 0) & (w1 <= 0) & (w2 <= 0)) |                 ((w0 >= 0) & (w1 >= 0) & (w2 >= 0))
            if not mask.any():
                continue
            wsum = w0 + w1 + w2
            wsum[wsum == 0] = 1e-12
            b0, b1, b2 = w0 / wsum, w1 / wsum, w2 / wsum

            zinv = b0 * inv_z[0] + b1 * inv_z[1] + b2 * inv_z[2]
            z = 1.0 / zinv
            sub = self.depth[min_y:max_y + 1, min_x:max_x + 1]
            visible = mask & (z < sub)
            if not visible.any():
                continue

            uo = (b0 * uv[0, 0] * inv_z[0] + b1 * uv[1, 0] * inv_z[1]
                  + b2 * uv[2, 0] * inv_z[2]) * z
            vo = (b0 * uv[0, 1] * inv_z[0] + b1 * uv[1, 1] * inv_z[1]
                  + b2 * uv[2, 1] * inv_z[2]) * z
            tx = np.clip((uo % 1.0) * tw, 0, tw - 1).astype(np.int32)
            ty = np.clip((1.0 - (vo % 1.0)) * th, 0, th - 1).astype(np.int32)

            shade = ambient
            for direction, energy in lights:
                shade = shade + energy * max(0.0, float(np.dot(normal, direction)))
            shade = min(shade, 1.25)

            texel = diffuse[ty, tx, :3] * diffuse_gain * shade
            glow = emissive[ty, tx, :3] * emissive_gain
            out = np.clip(texel + glow, 0, 255)

            region_color = self.color[min_y:max_y + 1, min_x:max_x + 1]
            region_color[visible] = out[visible]
            region_glow = self.glow[min_y:max_y + 1, min_x:max_x + 1]
            region_glow[visible] = glow[visible]
            sub[visible] = z[visible]

    def save(self, path, bloom=0.55):
        # Cheap bloom: the emissive contribution blurred wide and added back,
        # which is what the engine's glow post pass does to these pixels.
        out = self.color.copy()
        if bloom > 0:
            from PIL import ImageFilter
            glow_img = Image.fromarray(self.glow.clip(0, 255).astype(np.uint8))
            blurred = np.array(glow_img.filter(
                ImageFilter.GaussianBlur(radius=self.ss * 5)), dtype=np.float64)
            out = np.clip(out + blurred * bloom, 0, 255)
        img = Image.fromarray(out.astype(np.uint8))
        img = img.resize((self.out_w, self.out_h), Image.LANCZOS)
        img.save(path)
        print("wrote %s" % path)


def main():
    mesh_path, diffuse_path, lights_path, out_dir = sys.argv[1:5]
    os.makedirs(out_dir, exist_ok=True)
    mesh = load_obj(mesh_path)
    diffuse = np.array(Image.open(diffuse_path).convert("RGBA"), dtype=np.float64)
    emissive = np.array(Image.open(lights_path).convert("RGBA"), dtype=np.float64)
    name = os.path.splitext(os.path.basename(mesh_path))[0]

    shots = {
        # Three quarter beauty shot, slightly above, bow toward camera.
        "beauty": dict(eye=(3.4, 2.3, 4.4), target=(0, 0.25, 0), fov_deg=34),
        # Straight top down, the tactical camera's view.
        "top": dict(eye=(0.0, 6.4, 0.01), target=(0, 0, 0), fov_deg=34),
        # Aft quarter, where the drives glow.
        "aft": dict(eye=(-3.6, 1.7, -4.2), target=(0, 0.25, 0), fov_deg=34),
    }
    for shot, cam in shots.items():
        rend = Renderer(1280, 800)
        rend.background()
        rend.render(mesh, diffuse, emissive, **cam)
        rend.save(os.path.join(out_dir, "%s_%s.png" % (name, shot)))

    # Lights pass: hull dimmed to near dark so only the emissive reads,
    # matching the artist's *_lights presentation.
    rend = Renderer(1280, 800)
    rend.background(top=(4, 5, 8), bottom=(2, 2, 4))
    rend.render(mesh, diffuse, emissive, eye=(3.4, 2.3, 4.4),
                target=(0, 0.25, 0), fov_deg=34, ambient=0.06,
                lights=[((0.4, 0.8, 0.4), 0.06)], emissive_gain=2.4)
    rend.save(os.path.join(out_dir, "%s_lights.png" % name))


if __name__ == "__main__":
    main()
