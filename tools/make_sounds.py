"""Synthesises the weapon sound effects (no external samples needed)."""

import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "audio")


def lowpass(x, cutoff):
    dt = 1.0 / SR
    a = dt / (dt + 1.0 / (2.0 * np.pi * cutoff))
    y = np.empty_like(x)
    acc = 0.0
    for i in range(len(x)):
        acc += a * (x[i] - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 0 else x


def save(name, samples):
    samples = normalize(samples)
    pcm = np.clip(samples, -1.0, 1.0)
    pcm = (pcm * 32767).astype(np.int16)
    path = os.path.join(OUT, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(pcm.tobytes())
    print("wrote", path, f"{len(samples) / SR:.2f}s")


def gunshot():
    duration = 1.1
    n = int(SR * duration)
    t = np.arange(n) / SR
    rng = np.random.default_rng(11)
    noise = rng.standard_normal(n)

    crack = noise * np.exp(-t / 0.012)
    body = lowpass(noise, 900.0) * np.exp(-t / 0.055) * 0.9
    thump = (
        np.sin(2 * np.pi * 68.0 * t)
        + 0.5 * np.sin(2 * np.pi * 104.0 * t)
    ) * np.exp(-t / 0.06) * 0.8
    tail = lowpass(noise, 500.0) * np.exp(-np.maximum(t - 0.02, 0.0) / 0.3) * 0.22

    mix = crack * 0.9 + body + thump + tail

    # Cheap room: two attenuated delayed copies.
    for delay, gain in ((0.085, 0.25), (0.17, 0.14), (0.26, 0.08)):
        d = int(SR * delay)
        mix[d:] += mix[:-d] * gain

    mix = np.tanh(mix * 1.6)
    fade = int(SR * 0.01)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return mix


def click(name, count=1, spacing=0.08, bright=6000.0, decay=0.012, gain=0.7):
    duration = spacing * count + 0.15
    n = int(SR * duration)
    out = np.zeros(n)
    rng = np.random.default_rng(3)
    for i in range(count):
        start = int(SR * spacing * i)
        length = int(SR * 0.06)
        seg = int(min(length, n - start))
        tt = np.arange(seg) / SR
        burst = highpass(rng.standard_normal(seg), bright) * np.exp(-tt / decay)
        out[start:start + seg] += burst * gain * (0.8 + 0.2 * np.sin(i))
    return out


def reload_sequence():
    duration = 1.6
    n = int(SR * duration)
    out = np.zeros(n)
    rng = np.random.default_rng(5)

    def add(offset, length, cutoff, decay, gain):
        start = int(SR * offset)
        seg = int(SR * length)
        tt = np.arange(seg) / SR
        burst = highpass(rng.standard_normal(seg), cutoff) * np.exp(-tt / decay)
        out[start:start + seg] += burst * gain

    # cylinder release, six chambers, then the cylinder snapping shut
    add(0.02, 0.07, 3500.0, 0.02, 0.55)
    for i in range(6):
        add(0.18 + i * 0.13, 0.06, 5000.0, 0.012, 0.35)
    add(1.18, 0.12, 2200.0, 0.03, 0.8)

    return out


def shotgun_blast():
    """Deeper and longer than the revolver: a wide low boom plus a short crack."""
    duration = 1.6
    n = int(SR * duration)
    t = np.arange(n) / SR
    rng = np.random.default_rng(23)
    noise = rng.standard_normal(n)

    crack = highpass(noise, 1200.0) * np.exp(-t / 0.008) * 0.9
    boom = lowpass(noise, 420.0) * np.exp(-t / 0.10) * 1.3
    sub = (
        np.sin(2 * np.pi * 52.0 * t) + 0.45 * np.sin(2 * np.pi * 79.0 * t)
    ) * np.exp(-t / 0.085) * 0.95
    tail = lowpass(noise, 320.0) * np.exp(-np.maximum(t - 0.03, 0.0) / 0.5) * 0.3

    mix = crack * 0.85 + boom + sub + tail
    for delay, gain in ((0.105, 0.3), (0.22, 0.18), (0.36, 0.1)):
        d = int(SR * delay)
        mix[d:] += mix[:-d] * gain
    mix = np.tanh(mix * 1.5)
    fade = int(SR * 0.01)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return mix


def shotgun_dry():
    """Two hammer falls an instant apart."""
    return click("dry_shotgun", count=2, spacing=0.06, bright=1800.0, decay=0.018, gain=0.7)


def shotgun_reload():
    """Break-action open, two shells in, snap shut."""
    duration = 2.1
    n = int(SR * duration)
    out = np.zeros(n)
    rng = np.random.default_rng(9)

    def hit(offset, length, cutoff, decay, gain, thump=0.0, freq=120.0):
        start = int(SR * offset)
        seg = int(SR * length)
        tt = np.arange(seg) / SR
        sig = highpass(rng.standard_normal(seg), cutoff) * np.exp(-tt / decay)
        if thump > 0.0:
            sig = sig + thump * np.sin(2 * np.pi * freq * tt) * np.exp(-tt / (decay * 2.5))
        out[start:start + seg] += sig * gain

    hit(0.02, 0.18, 1800.0, 0.03, 0.9, 0.55, 140.0)
    hit(0.34, 0.10, 2500.0, 0.02, 0.55, 0.25, 200.0)
    hit(0.78, 0.10, 2500.0, 0.02, 0.55, 0.25, 180.0)
    hit(1.12, 0.09, 2200.0, 0.02, 0.5, 0.2, 220.0)
    hit(1.46, 0.20, 1400.0, 0.035, 1.0, 0.65, 120.0)

    return out


def headshot_pop():
    """Skull hit: a crisp metal-can crack with a ringing body and a short hiss."""
    duration = 0.55
    n = int(SR * duration)
    t = np.arange(n) / SR
    rng = np.random.default_rng(31)
    noise = rng.standard_normal(n)

    # The "tsss-click" of a can tab snapping, plus bone cracking.
    crack = highpass(noise, 2600.0) * np.exp(-t / 0.006)
    pop = lowpass(noise, 850.0) * np.exp(-t / 0.028) * 0.85
    crunch = highpass(noise, 900.0) * np.exp(-t / 0.05) * 0.4

    # Thin metal ring, slightly detuned so it does not sound like a beep.
    ring = (
        np.sin(2 * np.pi * 1965.0 * t) * 0.5
        + np.sin(2 * np.pi * 2807.0 * t) * 0.32
        + np.sin(2 * np.pi * 3924.0 * t) * 0.22
    ) * np.exp(-t / 0.075)

    hiss = lowpass(noise, 6500.0) * np.exp(-np.maximum(t - 0.015, 0.0) / 0.11) * 0.16

    mix = crack + pop + crunch + ring * 0.55 + hiss
    mix = np.tanh(mix * 1.35)
    fade = int(SR * 0.004)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return mix


def rifle_shot(duration=0.9, crack=0.007, body_cut=1400.0, body_decay=0.04,
               tail=0.25, thump=0.4, seed=41):
    """Generic rifle bang; the parameters decide AKM snappiness vs SVD boom."""
    n = int(SR * duration)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)

    crack_sig = highpass(noise, 2400.0) * np.exp(-t / crack)
    body = lowpass(noise, body_cut) * np.exp(-t / body_decay) * 0.95
    sub = (
        np.sin(2 * np.pi * 72.0 * t) + 0.4 * np.sin(2 * np.pi * 108.0 * t)
    ) * np.exp(-t / 0.07) * thump
    tail_sig = lowpass(noise, 420.0) * np.exp(-np.maximum(t - 0.02, 0.0) / tail) * 0.22

    mix = crack_sig * 1.1 + body + sub + tail_sig
    for delay, gain in ((0.09, 0.26), (0.21, 0.14), (0.36, 0.07)):
        d = int(SR * delay)
        mix[d:] += mix[:-d] * gain
    mix = np.tanh(mix * 1.4)
    fade = int(SR * 0.008)
    mix[:fade] *= np.linspace(0, 1, fade)
    mix[-fade:] *= np.linspace(1, 0, fade)
    return mix


def mag_reload(clicks=((0.03, 0.06), (0.22, 0.1), (0.55, 0.08), (1.15, 0.12))):
    """Magazine out, new one in, bolt forward."""
    duration = clicks[-1][0] + 0.35
    n = int(SR * duration)
    out = np.zeros(n)
    rng = np.random.default_rng(17)
    for offset, length in clicks:
        start = int(SR * offset)
        seg = int(SR * 0.18)
        tt = np.arange(seg) / SR
        burst = highpass(rng.standard_normal(seg), 1800.0) * np.exp(-tt / (length * 0.35))
        weight = 0.5 * np.sin(2 * np.pi * 150.0 * tt) * np.exp(-tt / (length * 0.5))
        out[start:start + seg] += (burst * 0.8 + weight) * 0.7
    return out


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("revolver_shot.wav", gunshot())
    save("revolver_dry.wav", click("dry", count=1, bright=2500.0, decay=0.02, gain=0.6))
    save("revolver_reload.wav", reload_sequence())
    save("shotgun_blast.wav", shotgun_blast())
    save("shotgun_dry.wav", shotgun_dry())
    save("shotgun_reload.wav", shotgun_reload())
    save("headshot.wav", headshot_pop())
    save("akm_shot.wav", rifle_shot(0.85, crack=0.006, body_cut=1700.0, body_decay=0.032,
                                    tail=0.2, thump=0.35, seed=51))
    save("akm_dry.wav", click("akm_dry", count=1, bright=2200.0, decay=0.018, gain=0.6))
    save("akm_reload.wav", mag_reload())
    save("svd_shot.wav", rifle_shot(1.5, crack=0.005, body_cut=850.0, body_decay=0.07,
                                    tail=0.5, thump=0.85, seed=77))
    save("svd_dry.wav", click("svd_dry", count=1, bright=2000.0, decay=0.02, gain=0.6))
    save("svd_reload.wav", mag_reload(clicks=((0.05, 0.07), (0.5, 0.1), (1.1, 0.09), (1.55, 0.13))))
