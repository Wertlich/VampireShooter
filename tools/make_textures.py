"""Generates small procedural textures used by the game (muzzle flash, spark)."""

import os

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


def muzzle_flash(size=256):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    cx = cy = (size - 1) / 2.0
    dx = (x - cx) / (size / 2.0)
    dy = (y - cy) / (size / 2.0)
    d = np.sqrt(dx * dx + dy * dy)
    ang = np.arctan2(dy, dx)

    core = np.exp(-((d * 9.0) ** 2))
    glow = np.exp(-((d * 4.2) ** 2))
    spikes = (np.abs(np.cos(ang * 3.0)) ** 10) * np.exp(-((d * 2.2) ** 2))
    rays = (np.abs(np.cos(ang * 6.0 + 0.5)) ** 22) * np.exp(-((d * 3.0) ** 2)) * 0.5

    alpha = np.clip(core * 1.0 + glow * 0.75 + spikes * 0.9 + rays, 0.0, 1.0)
    alpha = alpha ** 0.85

    hot = np.clip(core + spikes * 0.8, 0.0, 1.0)
    r = np.clip(1.0 * alpha + 0.2, 0, 1)
    g = np.clip((0.62 + 0.38 * hot) * alpha, 0, 1)
    b = np.clip((0.22 + 0.55 * hot) * alpha, 0, 1)

    rgba = np.stack([r, g, b, alpha], axis=-1)
    rgba = (rgba * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


def soft_dot(size=128):
    y, x = np.mgrid[0:size, 0:size].astype(np.float32)
    c = (size - 1) / 2.0
    d = np.sqrt((x - c) ** 2 + (y - c) ** 2) / (size / 2.0)
    a = np.clip(1.0 - d, 0.0, 1.0) ** 2.2
    rgba = np.stack([np.ones_like(a), a * 0.85, a * 0.55, a], axis=-1)
    return Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    muzzle_flash().save(os.path.join(OUT, "muzzle_flash.png"))
    soft_dot().save(os.path.join(OUT, "soft_dot.png"))
    print("textures written to", OUT)
