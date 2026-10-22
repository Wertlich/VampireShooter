"""Generates the AKM view-model textures: laminated wood and blued steel.

The source AKM model ships without UVs and without any textures at all (a dozen
flat grey materials), so the wood/metal look comes from procedurally baked
albedo + roughness + normal maps that the materials sample with triplanar
mapping. Grain and scratches run along U, which is what the side projections of
the stock and the handguards use, so they follow the length of the gun.

Run: python tools/make_akm_textures.py
"""

import os

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "textures")


# --- noise helpers ----------------------------------------------------------

def _upsample(grid, size):
    im = Image.fromarray((np.clip(grid, 0.0, 1.0) * 255).astype(np.uint8), "L")
    return np.asarray(im.resize(size, Image.BICUBIC)).astype(np.float32) / 255.0


def fbm(size, freq, octaves=4, seed=0, aniso=(1.0, 1.0), gain=0.5):
    """Fractal noise at the final resolution.

    `freq` is the number of cells across the texture for the first octave and
    `aniso` stretches it per axis: (1, 40) gives thin horizontal streaks.
    """
    rows, cols = size
    rng = np.random.default_rng(seed)
    total = np.zeros((rows, cols), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        fx = max(2, int(round(freq * aniso[0] * (2 ** o))))
        fy = max(2, int(round(freq * aniso[1] * (2 ** o))))
        grid = rng.random((fy, fx)).astype(np.float32)
        total += _upsample(grid, (cols, rows)) * amp
        norm += amp
        amp *= gain
    return total / max(norm, 1e-6)


def _normalise(a):
    lo, hi = float(a.min()), float(a.max())
    if hi - lo < 1e-6:
        return np.zeros_like(a)
    return (a - lo) / (hi - lo)


def _normal_from_height(height, strength=3.0):
    """OpenGL-style (+Y up) tangent-space normal map from a height field."""
    dx = np.gradient(height, axis=1) * strength
    dy = np.gradient(height, axis=0) * strength
    nx, ny, nz = -dx, -dy, np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / length * 0.5 + 0.5, ny / length * 0.5 + 0.5, nz / length * 0.5 + 0.5], axis=-1)
    return np.clip(rgb, 0.0, 1.0)


def _ramp(t, dark, mid, light):
    t = np.clip(t, 0.0, 1.0)[..., None]
    dark, mid, light = (np.array(c, dtype=np.float32) for c in (dark, mid, light))
    lower = dark + (mid - dark) * (t / 0.5)
    upper = mid + (light - mid) * ((t - 0.5) / 0.5)
    return np.where(t < 0.5, lower, upper)


def _save(arr, name):
    im = Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "RGB")
    im.save(os.path.join(OUT, name))
    print("   ", name, im.size)


def _save_gray(arr, name):
    im = Image.fromarray((np.clip(arr, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "L")
    im.save(os.path.join(OUT, name))
    print("   ", name, im.size)


# --- wood -------------------------------------------------------------------

def _grain_profile(rows, seed, count, width_range, strength):
    """1D profile of dark grain lines across the texture height."""
    rng = np.random.default_rng(seed)
    v = np.arange(rows, dtype=np.float32) / rows
    profile = np.zeros(rows, dtype=np.float32)
    centers = np.sort(rng.random(count))
    widths = rng.uniform(*width_range, count)
    strengths = rng.uniform(0.35, 1.0, count) ** 1.5
    for c, w, s in zip(centers, widths, strengths):
        d = ((v - c + 0.5) % 1.0) - 0.5   # tileable distance
        profile += np.exp(-((d / w) ** 2)) * s
    return np.clip(profile * strength, 0.0, 1.0)


def wood(size=1024):
    """AKM laminated birch: warm red-brown with straight, fine grain."""
    rows = cols = size
    rng = np.random.default_rng(7)

    # Two grain layers: broad early-wood bands plus fine late-wood lines.
    broad = _grain_profile(rows, 101, 22, (0.012, 0.034), 0.35)
    fine = _grain_profile(rows, 202, 120, (0.0018, 0.0055), 0.45)

    # Waviness: shift the profile along U so the lines are not perfectly straight.
    warp = fbm((32, cols), 3, 3, seed=303, aniso=(1.0, 0.15))
    warp = (_normalise(warp[0]) - 0.5) * rows * 0.035
    idx = (np.arange(rows, dtype=np.float32)[:, None] + warp[None, :]) % rows
    i0 = np.floor(idx).astype(np.int32)
    frac = idx - i0
    profile = (broad[i0 % rows] * (1 - frac) + broad[(i0 + 1) % rows] * frac) * 0.45 \
        + (fine[i0 % rows] * (1 - frac) + fine[(i0 + 1) % rows] * frac) * 0.30

    # Fibres along the grain, so a close-up does not dissolve into smooth bands.
    fibres = fbm((rows, cols), 4, 4, seed=404, aniso=(1.0, 26.0))
    fibres = _normalise(fibres)

    # Slow colour mottling and a little darker figure in the middle of the stock.
    mottle = fbm((rows, cols), 3, 3, seed=505)

    grain = np.clip(0.45 - profile + 0.20 * (fibres - 0.5) + 0.22 * (mottle - 0.5) - 0.02, 0.0, 1.0)

    # Pores: sparse short dashes along the grain.
    pores = np.zeros((rows, cols), dtype=np.float32)
    count = 2600
    py = rng.integers(0, rows, count)
    px = rng.integers(0, cols, count)
    plen = rng.integers(4, 16, count)
    for i in range(count):
        pores[py[i], px[i]:px[i] + plen[i]] = 1.0
    pores_im = Image.fromarray((pores * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.0))
    pores = np.asarray(pores_im).astype(np.float32) / 255.0

    tone = np.clip(grain - 0.40 * pores, 0.0, 1.0)
    albedo = _ramp(tone,
                   dark=(0.215, 0.100, 0.048),
                   mid=(0.360, 0.168, 0.072),
                   light=(0.520, 0.275, 0.120))
    albedo = np.stack([albedo[..., 0] * 1.03, albedo[..., 1] * 1.0, albedo[..., 2] * 0.92], axis=-1)

    rough = np.clip(0.42 + 0.24 * (1.0 - tone) + 0.10 * fibres, 0.0, 1.0)
    height = np.clip(0.40 * (0.45 - profile) + 0.20 * (1.0 - fibres) - 0.4 * pores, 0.0, 1.0)
    normal = _normal_from_height(height, strength=1.0)

    _save(albedo, "akm_wood_albedo.png")
    _save_gray(rough, "akm_wood_roughness.png")
    _save(normal, "akm_wood_normal.png")


# --- blued steel ------------------------------------------------------------

def metal(size=1024):
    """Blued steel: dark blue-grey with brushed streaks, scratches and pitting."""
    rows = cols = size
    rng = np.random.default_rng(9)

    bluing = fbm((rows, cols), 3, 4, seed=601)           # uneven heat bluing
    brushed = fbm((rows, cols), 6, 4, seed=602, aniso=(1.0, 30.0))  # long streaks along U
    brushed = _normalise(brushed)
    micro = fbm((rows, cols), 40, 4, seed=603)           # fine surface grain

    # Scratches: a few thin bright lines running along the barrel (U).
    scratches = np.zeros((rows, cols), dtype=np.float32)
    for _ in range(26):
        y = rng.integers(0, rows)
        x0 = rng.integers(0, cols)
        length = rng.integers(cols // 14, cols // 2)
        thickness = 1
        scratches[max(0, y - thickness):y + thickness + 1, x0:x0 + length] = 0.7
    scratches_im = Image.fromarray((scratches * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(1.2))
    scratches = np.asarray(scratches_im).astype(np.float32) / 255.0

    # Pitting: sparse rounded dark specks.
    pits = _normalise(fbm((rows, cols), 90, 3, seed=604))
    pits = np.clip((pits - 0.74) / 0.26, 0.0, 1.0)
    pits = np.asarray(Image.fromarray((pits * 255).astype(np.uint8), "L")
                      .filter(ImageFilter.GaussianBlur(0.7))).astype(np.float32) / 255.0

    tone = np.clip(0.50 + 0.30 * (bluing - 0.5) + 0.18 * (brushed - 0.5)
                   + 0.10 * (micro - 0.5) + 0.20 * scratches - 0.42 * pits, 0.0, 1.0)

    albedo = _ramp(tone,
                   dark=(0.090, 0.100, 0.115),
                   mid=(0.260, 0.280, 0.310),
                   light=(0.480, 0.500, 0.540))
    albedo = np.stack([albedo[..., 0] * 0.93, albedo[..., 1] * 1.0, albedo[..., 2] * 1.13], axis=-1)

    rough = np.clip(0.26 + 0.22 * pits + 0.10 * (1.0 - brushed) - 0.10 * scratches
                    + 0.10 * (bluing - 0.5) + 0.08 * (micro - 0.5), 0.05, 1.0)

    height = np.clip(1.0 - 0.60 * pits + 0.10 * (brushed - 0.5) + 0.06 * (micro - 0.5), 0.0, 1.0)
    normal = _normal_from_height(height, strength=1.6)

    _save(albedo, "akm_metal_albedo.png")
    _save_gray(rough, "akm_metal_roughness.png")
    _save(normal, "akm_metal_normal.png")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    wood()
    metal()
    print("AKM textures written to", OUT)
