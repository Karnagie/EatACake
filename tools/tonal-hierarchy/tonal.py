#!/usr/bin/env python3
"""tonal.py — UI tonal-hierarchy analyzer.

Evaluates WHERE a UI screenshot pulls the eye and whether that matches the
intended hierarchy. The brain reads tonal value (perceptual lightness) first:
high contrast attracts attention. A Buy button should be loud; a background
should be quiet. This tool measures that objectively.

Pipeline (all perceptual, CIELAB):
  sRGB -> linear -> CIELAB (L* = tonal value, a*/b* = color opponency)
  - gray.png       L* grayscale ("squint test" image)
  - bands.png      L* posterized into 5 value bands (the value layers)
  - saliency.png   multi-scale center-surround contrast in L*, a*, b*
                   (a lightweight Itti-Koch model: what pops, including
                   saturated color patches whose L* blends in)
  - hotspots.png   auto-extracted attention magnets, ranked
  - annotated.png  region boxes: intended level vs measured attention rank
  - report.md/json metrics, findings (with severities), hierarchy score 0-100

Region spec (JSON): {"viewport": [w,h] (optional), "regions": [
    {"name": "buy-button", "rect": [x,y,w,h], "level": 1, "role": "cta"},
    ...]}
  level 1 = must draw the eye first (primary CTA)
  level 2 = second read (active nav, key info, hero content)
  level 3 = supporting content (inactive nav, body, decor)
  level 4 = chrome / background (should recede)
  role (optional, informs rules): cta, tab-active, tab-inactive, title,
       content, container, background, decor
  "ignore": true excludes a region from ranks/score (e.g. avatar photo).
  rects are in image pixels, or in viewport coords if "viewport" is given.

Commands:
  analyze IMG [--regions R.json] [--out DIR]
  compare BEFORE.png AFTER.png [--regions R.json] [--regions-after R2.json]
  selftest [--keep DIR]
  listen [--port 8788] [--out regions.json] [--timeout 120]
         (one-shot HTTP region receiver; body must be valid JSON)

Requires: Python 3.9+, Pillow, numpy. No other dependencies.
"""

import argparse
import json
import math
import os
import sys
import tempfile

import numpy as np
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------------------
# Thresholds (all overridable via --config JSON). Calibrated on the selftest
# fixtures and a real production shop screen; see README.md for meaning.
# ---------------------------------------------------------------------------
DEFAULT_THRESHOLDS = {
    "invert_margin": 1.15,   # lower-level region must beat higher one by 15%
    "invert_floor": 0.30,    # ...and be at least this loud in absolute terms
                             # (below this both elements are visually quiet —
                             # rank noise, not a hierarchy problem; calibrated
                             # on a real shop screen where genuinely loud
                             # elements measured 0.45+)
    "cta_min_dl": 22.0,      # min |dL*| a level-1 element needs vs surround
    "cta_top_rank": 2,       # level-1 must place in attention top-N
    "bg_internal_std": 16.0, # internal L* std above this = noisy background
    "bg_density_ratio": 1.3, # bg mean saliency above image mean = loud bg
    "sink_share": 0.18,      # level>=3 region holding this saliency share
    "low_sep_dl": 12.0,      # level<=2 region below this dL* = blends in
    "text_min_contrast": 30.0,  # title/text roles: min P95-P5 L* spread
                                # (glyphs vs their backdrop, not zone mean)
    "crowded_ratio": 0.8,    # regions within 80% of top saliency...
    "crowded_max": 3,        # ...more than this many = nothing leads
    "level_sep_dl": 12.0,    # median L* gap between adjacent levels (info)
    "hotspot_pctl": 97.0,    # saliency percentile that defines a hotspot
    "hotspot_min_frac": 0.0002,  # min component area (fraction of image)
    "blur_dl": 8.0,          # post-heavy-blur |dL*| below this = tonally gone
    "blur_chroma": 10.0,     # post-blur chroma distance below this = color gone
}

BLUR_HEAVY_FRAC = 0.025      # heavy-blur sigma, fraction of max dim
BLUR_EXTREME_FRAC = 0.05     # "across the room" second level

WORK_MAX_DIM = 1100          # analysis resolution (max of w,h)
SALIENCY_SCALES = (0.02, 0.06, 0.12)   # center-surround sigmas, frac of dim
SALIENCY_WEIGHTS = {"L": 0.5, "a": 0.25, "b": 0.25}
BAND_EDGES = (0, 20, 40, 60, 80, 100)  # L* value bands (5 layers)

LEVEL_COLORS = {1: (53, 224, 106), 2: (79, 195, 247),
                3: (255, 183, 77), 4: (158, 158, 158)}
SEVERITY_ORDER = {"CRITICAL": 0, "WARN": 1, "INFO": 2}


# ---------------------------------------------------------------------------
# Color math: sRGB -> linear -> CIELAB
# ---------------------------------------------------------------------------
def srgb_to_linear(rgb01: np.ndarray) -> np.ndarray:
    lo = rgb01 / 12.92
    hi = ((rgb01 + 0.055) / 1.055) ** 2.4
    return np.where(rgb01 <= 0.04045, lo, hi)


def rgb_to_lab(rgb01: np.ndarray):
    """rgb01: HxWx3 float in [0,1]. Returns (L, a, b) float32 arrays.
    L in [0,100]; a,b roughly [-100,100]."""
    lin = srgb_to_linear(rgb01.astype(np.float64))
    r, g, b = lin[..., 0], lin[..., 1], lin[..., 2]
    # sRGB D65 primaries
    x = 0.4124564 * r + 0.3575761 * g + 0.1804375 * b
    y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
    z = 0.0193339 * r + 0.1191920 * g + 0.9503041 * b
    xn, yn, zn = 0.95047, 1.0, 1.08883
    eps, kap = (6 / 29) ** 3, (29 / 6) ** 2 / 3

    def f(t):
        return np.where(t > eps, np.cbrt(t), kap * t + 4 / 29)

    fx, fy, fz = f(x / xn), f(y / yn), f(z / zn)
    L = 116 * fy - 16
    a = 500 * (fx - fy)
    bb = 200 * (fy - fz)
    return (L.astype(np.float32), a.astype(np.float32), bb.astype(np.float32),
            y.astype(np.float32))


# ---------------------------------------------------------------------------
# Fast blur: 3 iterated box blurs ~ gaussian; O(N) via cumulative sums
# ---------------------------------------------------------------------------
def _box_blur_axis(a: np.ndarray, r: int, axis: int) -> np.ndarray:
    if r <= 0:
        return a
    a2 = np.moveaxis(a, axis, 0)
    n = a2.shape[0]
    pad = np.concatenate(
        [np.repeat(a2[:1], r, axis=0), a2, np.repeat(a2[-1:], r, axis=0)], 0)
    c = np.cumsum(pad, axis=0, dtype=np.float64)
    c = np.concatenate([np.zeros_like(c[:1]), c], 0)
    out = (c[2 * r + 1:] - c[:-(2 * r + 1)]) / (2 * r + 1)
    return np.moveaxis(out[:n].astype(np.float32), 0, axis)


def gaussian_blur(a: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.5:
        return a
    # box width for 3 passes approximating gaussian sigma
    r = max(1, int(round(math.sqrt(sigma * sigma * 12 / 3 + 1) / 2)))
    out = a
    for _ in range(3):
        out = _box_blur_axis(out, r, 0)
        out = _box_blur_axis(out, r, 1)
    return out


def linear_to_srgb(lin: np.ndarray) -> np.ndarray:
    lo = lin * 12.92
    hi = 1.055 * np.clip(lin, 0, None) ** (1 / 2.4) - 0.055
    return np.where(lin <= 0.0031308, lo, hi)


def compute_blur_maps(rgb01: np.ndarray, L, a, b):
    """The squint test as literal images: heavy gaussian blur in COLOR
    (linear-light, so bright saturated patches survive honestly) and in L*
    (pure tonal survival). Returns display images + the blurred Lab maps the
    survival metrics read."""
    dim = max(L.shape)
    lin = srgb_to_linear(rgb01.astype(np.float64)).astype(np.float32)
    out = {}
    for tag, frac in (("heavy", BLUR_HEAVY_FRAC), ("extreme", BLUR_EXTREME_FRAC)):
        sigma = frac * dim
        blurred = np.stack(
            [gaussian_blur(lin[..., i], sigma) for i in range(3)], axis=-1)
        out[f"color_{tag}"] = np.clip(
            linear_to_srgb(blurred) * 255.0, 0, 255).astype(np.uint8)
        Lb = gaussian_blur(L, sigma)
        out[f"gray_{tag}"] = np.clip(Lb / 100.0 * 255.0, 0, 255).astype(np.uint8)
        if tag == "heavy":
            out["Lb"] = Lb
            out["ab"] = gaussian_blur(a, sigma)
            out["bb"] = gaussian_blur(b, sigma)
    return out


# ---------------------------------------------------------------------------
# Saliency: multi-scale center-surround contrast in Lab
# ---------------------------------------------------------------------------
def compute_saliency(L, a, b):
    dim = max(L.shape)
    chans = {"L": L, "a": a, "b": b}
    total = np.zeros_like(L, dtype=np.float32)
    for name, ch in chans.items():
        acc = np.zeros_like(L, dtype=np.float32)
        for frac in SALIENCY_SCALES:
            sigma = frac * dim
            acc += np.abs(ch - gaussian_blur(ch, sigma))
        acc /= len(SALIENCY_SCALES)
        p99 = float(np.percentile(acc, 99))
        if p99 > 1e-6:
            acc = np.clip(acc / p99, 0, 1)
        total += SALIENCY_WEIGHTS[name] * acc
    total = gaussian_blur(total, 0.008 * dim)
    mx = float(total.max())
    if mx > 1e-6:
        total /= mx
    return total


# ---------------------------------------------------------------------------
# Connected components (8-connectivity, run-based union-find)
# ---------------------------------------------------------------------------
def label_components(mask: np.ndarray):
    parent = {}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(x, y):
        rx, ry = find(x), find(y)
        if rx != ry:
            parent[ry] = rx

    h, w = mask.shape
    labels = np.zeros((h, w), dtype=np.int32)
    next_label = 1
    prev_runs = []
    for y in range(h):
        row = mask[y]
        if not row.any():
            prev_runs = []
            continue
        d = np.diff(row.astype(np.int8))
        starts = (np.where(d == 1)[0] + 1).tolist()
        ends = (np.where(d == -1)[0] + 1).tolist()
        if row[0]:
            starts = [0] + starts
        if row[-1]:
            ends = ends + [w]
        runs = []
        for s, e in zip(starts, ends):
            lab = 0
            for ps, pe, pl in prev_runs:
                if ps < e + 1 and pe > s - 1:  # 8-connected overlap
                    root = find(pl)
                    if lab == 0:
                        lab = root
                    elif root != lab:
                        union(lab, root)
                        lab = find(lab)
            if lab == 0:
                lab = next_label
                parent[lab] = lab
                next_label += 1
            labels[y, s:e] = lab
            runs.append((s, e, lab))
        prev_runs = runs
    if next_label > 1:
        # resolve to canonical roots, compact ids
        roots = {}
        flat = labels.ravel()
        nz = flat > 0
        uniq = np.unique(flat[nz])
        remap = np.zeros(int(uniq.max()) + 1, dtype=np.int32)
        nid = 1
        for u in uniq:
            r = find(int(u))
            if r not in roots:
                roots[r] = nid
                nid += 1
            remap[u] = roots[r]
        labels = remap[labels]
    return labels


# ---------------------------------------------------------------------------
# Rendering helpers
# ---------------------------------------------------------------------------
_INFERNO_STOPS = [(0.0, (0, 0, 4)), (0.25, (87, 16, 110)),
                  (0.5, (188, 55, 84)), (0.75, (249, 142, 9)),
                  (1.0, (252, 255, 164))]


def colormap_inferno(v01: np.ndarray) -> np.ndarray:
    v = np.clip(v01, 0, 1)
    out = np.zeros(v.shape + (3,), dtype=np.float32)
    for (p0, c0), (p1, c1) in zip(_INFERNO_STOPS, _INFERNO_STOPS[1:]):
        m = (v >= p0) & (v <= p1)
        t = np.zeros_like(v)
        span = p1 - p0
        t[m] = (v[m] - p0) / span
        for i in range(3):
            out[..., i][m] = c0[i] + (c1[i] - c0[i]) * t[m]
    return out.astype(np.uint8)


def load_font(px: int):
    for name in ("segoeuib.ttf", "arialbd.ttf", "segoeui.ttf", "arial.ttf",
                 "DejaVuSans-Bold.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, px)
        except Exception:
            continue
    return ImageFont.load_default()


def draw_label(draw: ImageDraw.ImageDraw, xy, text, font, fg=(255, 255, 255),
               bg=(0, 0, 0)):
    x, y = xy
    try:
        l, t, r, b = draw.textbbox((x, y), text, font=font)
    except Exception:
        w, h = draw.textsize(text, font=font)
        l, t, r, b = x, y, x + w, y + h
    pad = 2
    draw.rectangle([l - pad, t - pad, r + pad, b + pad], fill=bg)
    draw.text((x, y), text, font=font, fill=fg)


# ---------------------------------------------------------------------------
# Regions
# ---------------------------------------------------------------------------
def load_regions(path, image_size):
    with open(path, "r", encoding="utf-8-sig") as f:
        data = json.load(f)
    if isinstance(data, list):
        data = {"regions": data}
    regions = data.get("regions", [])
    vw, vh = image_size
    sx = sy = 1.0
    vp = data.get("viewport")
    if vp and len(vp) == 2 and vp[0] > 0 and vp[1] > 0:
        sx, sy = image_size[0] / vp[0], image_size[1] / vp[1]
    out, warnings = [], []
    for i, r in enumerate(regions):
        name = str(r.get("name", f"region-{i}"))
        rect = r.get("rect")
        if not rect or len(rect) != 4:
            warnings.append(f"region '{name}': missing/bad rect - skipped")
            continue
        x, y, w, h = [float(v) for v in rect]
        x, y, w, h = x * sx, y * sy, w * sx, h * sy
        x0, y0 = max(0.0, x), max(0.0, y)
        x1, y1 = min(vw, x + w), min(vh, y + h)
        if x1 - x0 < 4 or y1 - y0 < 4:
            warnings.append(f"region '{name}': degenerate after clamping - "
                            f"skipped")
            continue
        level = r.get("level")
        if level is None and not r.get("ignore"):
            warnings.append(f"region '{name}': no level given, assuming 3")
            level = 3
        out.append({
            "name": name,
            "rect": [x0, y0, x1 - x0, y1 - y0],
            "level": int(level) if level is not None else None,
            "role": (r.get("role") or "").lower() or None,
            "ignore": bool(r.get("ignore", False)),
        })
    return out, warnings


def region_metrics(regions, L, S, ylin, scale, blur=None):
    """Compute per-region stats on working-scale maps. scale maps original
    image px -> working px. `blur` (from compute_blur_maps) adds squint-test
    survival stats: what still separates from its surround after heavy
    blur."""
    h, w = L.shape
    total_s = float(S.sum()) or 1e-6
    img_mean_s = float(S.mean())
    for reg in regions:
        x, y, rw, rh = [v * scale for v in reg["rect"]]
        x0 = max(0, min(int(round(x)), w - 1))
        y0 = max(0, min(int(round(y)), h - 1))
        x1 = max(x0 + 1, min(w, int(round(x + rw))))
        y1 = max(y0 + 1, min(h, int(round(y + rh))))
        subL = L[y0:y1, x0:x1]
        subS = S[y0:y1, x0:x1]
        subY = ylin[y0:y1, x0:x1]
        pad = int(min(40, max(6, 0.18 * min(x1 - x0, y1 - y0))))
        ex0, ey0 = max(0, x0 - pad), max(0, y0 - pad)
        ex1, ey1 = min(w, x1 + pad), min(h, y1 + pad)
        ring_mask = np.ones((ey1 - ey0, ex1 - ex0), dtype=bool)
        ring_mask[y0 - ey0:y1 - ey0, x0 - ex0:x1 - ex0] = False
        ringL = L[ey0:ey1, ex0:ex1][ring_mask]
        ringY = ylin[ey0:ey1, ex0:ex1][ring_mask]
        mean_l = float(subL.mean())
        ring_l = float(ringL.mean()) if ringL.size else mean_l
        y_r = float(subY.mean())
        y_s = float(ringY.mean()) if ringY.size else y_r
        wcag = (max(y_r, y_s) + 0.05) / (min(y_r, y_s) + 0.05)
        hist, _ = np.histogram(subL, bins=list(BAND_EDGES))
        reg["metrics"] = {
            "text_contrast": float(np.percentile(subL, 95) -
                                   np.percentile(subL, 5)),
            "mean_l": mean_l,
            "std_l": float(subL.std()),
            "ring_l": ring_l,
            "dl_surround": mean_l - ring_l,
            "wcag_vs_surround": wcag,
            "sal_mean": float(subS.mean()),
            "sal_share": float(subS.sum()) / total_s,
            "sal_density_ratio": (float(subS.mean()) / img_mean_s
                                  if img_mean_s > 1e-9 else 0.0),
            "area_share": subL.size / (h * w),
            "band_hist": (hist / max(1, subL.size)).round(3).tolist(),
            "work_rect": [x0, y0, x1 - x0, y1 - y0],
        }
        if blur is not None:
            sub_lb = blur["Lb"][y0:y1, x0:x1]
            ring_lb = blur["Lb"][ey0:ey1, ex0:ex1][ring_mask]
            m = reg["metrics"]
            if ring_lb.size:
                m["dl_blur"] = float(sub_lb.mean()) - float(ring_lb.mean())
                da = (float(blur["ab"][y0:y1, x0:x1].mean())
                      - float(blur["ab"][ey0:ey1, ex0:ex1][ring_mask].mean()))
                db = (float(blur["bb"][y0:y1, x0:x1].mean())
                      - float(blur["bb"][ey0:ey1, ex0:ex1][ring_mask].mean()))
                m["chroma_blur"] = math.hypot(da, db)
            else:
                m["dl_blur"] = 0.0
                m["chroma_blur"] = 0.0
    # Residual metrics: a container/background region inherits its children's
    # saliency, which makes raw share/mean meaningless for it. Measure the
    # region MINUS any annotated region mostly inside it.
    live = [r for r in regions if not r["ignore"]]
    for reg in live:
        rx, ry, rw2, rh2 = reg["metrics"]["work_rect"]
        # inset so the region's own boundary transition doesn't count as
        # internal contrast
        inset = max(2, int(0.03 * min(rw2, rh2)))
        x0, y0 = rx + inset, ry + inset
        w0, h0 = max(1, rw2 - 2 * inset), max(1, rh2 - 2 * inset)
        area = w0 * h0
        mask = np.ones((h0, w0), dtype=bool)
        # mask ALL other regions mostly inside this one — including ignored
        # ones (an ignored avatar photo must not inflate its container's
        # residual noise/saliency)
        for other in regions:
            if other is reg:
                continue
            ox, oy, ow, oh = other["metrics"]["work_rect"]
            ix0, iy0 = max(x0, ox), max(y0, oy)
            ix1 = min(x0 + w0, ox + ow)
            iy1 = min(y0 + h0, oy + oh)
            if ix1 <= ix0 or iy1 <= iy0:
                continue
            inter = (ix1 - ix0) * (iy1 - iy0)
            if inter / (ow * oh) > 0.6 and ow * oh < 0.9 * area:
                mask[iy0 - y0:iy1 - y0, ix0 - x0:ix1 - x0] = False
        m = reg["metrics"]
        if mask.mean() < 0.15 or w0 < 4 or h0 < 4:
            m["sal_eff"] = m["sal_mean"]
            m["std_eff"] = m["std_l"]
            m["density_eff"] = m["sal_density_ratio"]
        else:
            subL = L[y0:y0 + h0, x0:x0 + w0][mask]
            subS = S[y0:y0 + h0, x0:x0 + w0][mask]
            m["sal_eff"] = float(subS.mean())
            m["std_eff"] = float(subL.std())
            m["density_eff"] = (float(subS.mean()) / img_mean_s
                                if img_mean_s > 1e-9 else 0.0)
            m["residual"] = not bool(mask.all())
    live.sort(key=lambda r: -r["metrics"]["sal_eff"])
    for i, r in enumerate(live):
        r["metrics"]["attention_rank"] = i + 1
    return regions


def _rects_nested(a, b):
    """True if one region's rect covers >60% of the other's area."""
    ax, ay, aw, ah = a["rect"]
    bx, by, bw, bh = b["rect"]
    ix = max(0.0, min(ax + aw, bx + bw) - max(ax, bx))
    iy = max(0.0, min(ay + ah, by + bh) - max(ay, by))
    inter = ix * iy
    return inter > 0.6 * min(aw * ah, bw * bh)


# ---------------------------------------------------------------------------
# Hotspots
# ---------------------------------------------------------------------------
def extract_hotspots(S, th_pctl, min_frac, inv_scale, max_spots=8):
    thresh = max(float(np.percentile(S, th_pctl)), 0.30)
    mask = S >= thresh
    labels = label_components(mask)
    n = int(labels.max())
    spots = []
    min_px = max(4, int(min_frac * S.size))
    for lab in range(1, n + 1):
        ys, xs = np.where(labels == lab)
        if ys.size < min_px:
            continue
        vals = S[ys, xs]
        spots.append({
            "mass": float(vals.sum()),
            "peak": float(vals.max()),
            "bbox": [float(xs.min() * inv_scale), float(ys.min() * inv_scale),
                     float((xs.max() - xs.min() + 1) * inv_scale),
                     float((ys.max() - ys.min() + 1) * inv_scale)],
            "centroid": [float(xs.mean() * inv_scale),
                         float(ys.mean() * inv_scale)],
        })
    spots.sort(key=lambda s: -s["mass"])
    total = sum(s["mass"] for s in spots) or 1e-6
    for i, s in enumerate(spots[:max_spots]):
        s["rank"] = i + 1
        s["mass_share"] = s["mass"] / total
    return spots[:max_spots]


def hotspot_region(spot, regions):
    """Smallest region containing the hotspot centroid (ignored regions
    included — a hotspot on an annotated-ignore photo must attribute to the
    photo, not to its enclosing panel)."""
    cx, cy = spot["centroid"]
    best = None
    for r in regions:
        x, y, w, h = r["rect"]
        if x <= cx <= x + w and y <= cy <= y + h:
            if best is None or w * h < best["rect"][2] * best["rect"][3]:
                best = r
    return best


# ---------------------------------------------------------------------------
# Findings engine
# ---------------------------------------------------------------------------
def build_findings(regions, hotspots, th):
    findings = []
    active = [r for r in regions if not r["ignore"] and r["level"] is not None]

    def add(sev, code, msg, fix, region=None):
        findings.append({"severity": sev, "code": code, "message": msg,
                         "fix": fix, "region": region})

    # F1 inverted hierarchy — ELEMENT vs element only: containers and
    # backgrounds are surfaces, and chrome (scrollbars, dividers, frames) is
    # infrastructure — none of them compete for attention as elements; they
    # are judged by the background rules instead. Nested pairs are skipped
    # (a parent's number includes the child's).
    # Saliency is max-normalized PER IMAGE, so the louder element must also
    # be in the loud half of the screen (>= median): two elements at the
    # quiet end of the ranking are rank noise, not a hierarchy problem.
    elements = [r for r in active
                if r["role"] not in ("container", "background", "chrome")]
    med_sal = (float(np.median([r["metrics"]["sal_eff"] for r in elements]))
               if elements else 0.0)
    loud_gate = max(th["invert_floor"], med_sal)
    reported = set()
    for a_ in elements:
        for b_ in elements:
            if a_["level"] >= b_["level"] or _rects_nested(a_, b_):
                continue
            sa = a_["metrics"]["sal_eff"]
            sb = b_["metrics"]["sal_eff"]
            if sb > max(sa * th["invert_margin"], loud_gate) and \
                    (a_["name"] not in reported):
                add("CRITICAL", "inverted-hierarchy",
                    f"'{b_['name']}' (level {b_['level']}, saliency "
                    f"{sb:.2f}) out-shouts '{a_['name']}' (level "
                    f"{a_['level']}, saliency {sa:.2f}).",
                    f"Quiet '{b_['name']}' (pull its value toward its "
                    f"surround) and/or push '{a_['name']}''s contrast up "
                    f"until the ranking matches intent.",
                    region=a_["name"])
                reported.add(a_["name"])

    # F2 flat primary
    for r in active:
        if r["level"] != 1:
            continue
        m = r["metrics"]
        if abs(m["dl_surround"]) < th["cta_min_dl"] or \
                m["attention_rank"] > th["cta_top_rank"]:
            add("CRITICAL", "flat-primary",
                f"Primary '{r['name']}' has dL*={m['dl_surround']:+.0f} vs "
                f"surround and attention rank #{m['attention_rank']} — the "
                f"main action does not lead.",
                f"Give it the strongest value step on screen: |dL*| >= "
                f"{th['cta_min_dl']:.0f} vs surround (darken/lighten its "
                f"face, add its accent only here).", region=r["name"])

    # F3 attention sink (backgrounds are handled by noisy-background; the
    # share test needs density too, or big regions trip it by area alone)
    for r in active:
        if r["level"] < 3 or r["role"] == "background":
            continue
        m = r["metrics"]
        is_container = r["role"] == "container"
        share_hit = (not is_container and m["sal_share"] > th["sink_share"]
                     and m["sal_density_ratio"] > 1.5)
        if m["attention_rank"] == 1 or share_hit:
            add("CRITICAL", "attention-sink",
                f"'{r['name']}' (level {r['level']}) is an attention magnet: "
                f"rank #{m['attention_rank']}, {m['sal_share'] * 100:.0f}% of "
                f"total saliency — but it is not a priority element.",
                f"Pull its value toward its surround (target |dL*| <= "
                f"{th['low_sep_dl']:.0f}) or desaturate; reserve that "
                f"contrast for level-1/2 elements.", region=r["name"])

    # F4 noisy background / container
    for r in active:
        is_bg = r["level"] == 4 or (r["role"] in ("background", "container"))
        if not is_bg:
            continue
        m = r["metrics"]
        if m["std_eff"] > th["bg_internal_std"] or \
                m["density_eff"] > th["bg_density_ratio"]:
            add("WARN", "noisy-background",
                f"'{r['name']}' should recede but is busy: internal L* std "
                f"{m['std_eff']:.0f}, saliency density {m['density_eff']:.1f}x "
                f"image mean (own pixels, children excluded).",
                "Flatten it: fewer internal value steps (keep decoration "
                "within one value band, ~dL* <= 10).", region=r["name"])

    # F5 low separation for important elements
    flagged = {f["region"] for f in findings if f["code"] == "flat-primary"}
    for r in active:
        if r["level"] > 2 or r["name"] in flagged or r["level"] is None:
            continue
        if r["role"] in ("background", "container"):
            continue
        m = r["metrics"]
        if r["role"] in ("title", "text"):
            # a text zone's mean is dominated by its backdrop; what matters
            # is the glyph-vs-backdrop spread inside the zone
            if m["text_contrast"] < th["text_min_contrast"]:
                add("WARN", "low-separation",
                    f"Text '{r['name']}' (level {r['level']}) has weak glyph "
                    f"contrast: L* spread {m['text_contrast']:.0f} "
                    f"(want >= {th['text_min_contrast']:.0f}).",
                    "Lighten/darken the text or its backdrop until the "
                    "glyphs separate.", region=r["name"])
        elif abs(m["dl_surround"]) < th["low_sep_dl"]:
            add("WARN", "low-separation",
                f"'{r['name']}' (level {r['level']}) blends into its "
                f"surround: dL*={m['dl_surround']:+.0f}.",
                f"Separate it by at least {th['low_sep_dl']:.0f} L* from "
                f"what's behind it.", region=r["name"])

    # F6 crowded top layer
    ranked = sorted((r for r in active), key=lambda r: -r["metrics"]["sal_eff"])
    if ranked:
        top = ranked[0]["metrics"]["sal_eff"]
        loud = [r for r in ranked
                if r["metrics"]["sal_eff"] >= th["crowded_ratio"] * top]
        if len(loud) > th["crowded_max"]:
            names = ", ".join(f"'{r['name']}'" for r in loud[:6])
            add("WARN", "crowded-top",
                f"{len(loud)} regions compete within "
                f"{int((1 - th['crowded_ratio']) * 100)}% of the top "
                f"saliency ({names}) — nothing leads.",
                "Pick ONE leader per screen; demote the rest a full value "
                "step.")

    # F7 level value layering (info)
    by_level = {}
    for r in active:
        by_level.setdefault(r["level"], []).append(r["metrics"]["mean_l"])
    lv = sorted(by_level)
    for l0, l1 in zip(lv, lv[1:]):
        d = abs(float(np.median(by_level[l0])) -
                float(np.median(by_level[l1])))
        if d < th["level_sep_dl"]:
            add("INFO", "level-blend",
                f"Levels {l0} and {l1} occupy the same value band (median "
                f"L* gap {d:.0f}) — they read as one layer.",
                "Assign each level its own value range (squint test: levels "
                "should be separable in the bands image).")

    # F9 blur-invisible — the squint test (children may not read at all: an
    # element that vanishes under heavy blur is carried by TEXT alone, or by
    # nothing). Applies to important elements; text zones are exempt from
    # the CRITICAL tier (fine print legitimately dissolves — the ELEMENT
    # carrying it must not).
    for r in active:
        m = r["metrics"]
        if "dl_blur" not in m or r["level"] is None or r["level"] > 2:
            continue
        # text ALWAYS dissolves under blur — that is expected, not a defect;
        # the ELEMENT carrying the text is what must survive (rule lives in
        # the squint-test skill)
        if r["role"] in ("container", "background", "chrome", "title", "text"):
            continue
        if abs(m["dl_blur"]) < th["blur_dl"] and \
                m["chroma_blur"] < th["blur_chroma"]:
            sev = ("CRITICAL" if r["role"] in ("cta", "tab-active")
                   else "WARN")
            add(sev, "blur-invisible",
                f"'{r['name']}' (level {r['level']}) DISSOLVES under heavy "
                f"blur (dL* {m['dl_blur']:+.0f}, chroma "
                f"{m['chroma_blur']:.0f}) — at a squint it is part of the "
                f"background.",
                "Give it blur-proof mass: a bigger/bolder color field, a "
                "value step vs its surround, or a larger icon — outlines "
                "and text do not survive blur.", region=r["name"])

    # F8 stray hotspot (attention where no important region is)
    for s in hotspots[:2]:
        host = hotspot_region(s, regions)
        if host is not None and host["ignore"]:
            continue  # annotated-ignore content is EXPECTED to attract
        if host is None or (host["level"] is not None and host["level"] >= 3):
            where = (f"inside '{host['name']}'" if host
                     else f"at ({s['centroid'][0]:.0f}, "
                          f"{s['centroid'][1]:.0f})")
            add("WARN", "stray-hotspot",
                f"Attention hotspot #{s['rank']} "
                f"({s['mass_share'] * 100:.0f}% of hotspot mass) lands "
                f"{where}, which is not a level-1/2 element.",
                "Either promote that element intentionally or quiet it; "
                "check hotspots.png.")

    findings.sort(key=lambda f: SEVERITY_ORDER[f["severity"]])
    return findings


# ---------------------------------------------------------------------------
# Hierarchy score
# ---------------------------------------------------------------------------
def hierarchy_score(regions, th):
    active = [r for r in regions if not r["ignore"] and r["level"] is not None]
    if len(active) < 2:
        return None
    parts = {}
    # 45: pairwise rank agreement between intent and measured saliency
    conc = tot = 0
    for a_ in active:
        for b_ in active:
            if a_["level"] < b_["level"] and not _rects_nested(a_, b_):
                tot += 1
                if a_["metrics"]["sal_eff"] >= b_["metrics"]["sal_eff"]:
                    conc += 1
    if tot:
        parts["rank_agreement"] = (45.0, 45.0 * conc / tot)
    # 25: primary prominence
    l1 = [r for r in active if r["level"] == 1]
    if l1:
        best = min(l1, key=lambda r: r["metrics"]["attention_rank"])
        rank = best["metrics"]["attention_rank"]
        parts["primary_leads"] = (25.0, 25.0 * max(0.0, 1 - (rank - 1) / 3))
    # 20: background quietness
    bgs = [r for r in active
           if r["level"] == 4 or r["role"] == "background"]
    if bgs:
        top = max(r["metrics"]["sal_eff"] for r in active) or 1e-6
        loud = max(r["metrics"]["sal_eff"] / top for r in bgs)
        parts["background_quiet"] = (20.0, 20.0 * max(0.0, 1 - loud * 1.5))
    # 10: value layering between adjacent levels
    by_level = {}
    for r in active:
        by_level.setdefault(r["level"], []).append(r["metrics"]["mean_l"])
    lv = sorted(by_level)
    if len(lv) > 1:
        gaps = [abs(float(np.median(by_level[l0])) -
                    float(np.median(by_level[l1])))
                for l0, l1 in zip(lv, lv[1:])]
        parts["value_layering"] = (
            10.0, 10.0 * min(1.0, min(gaps) / max(1e-6, th["level_sep_dl"])))
    max_total = sum(p[0] for p in parts.values())
    got = sum(p[1] for p in parts.values())
    return {
        "score": round(100.0 * got / max_total, 1) if max_total else None,
        "parts": {k: {"max": v[0], "got": round(v[1], 1)}
                  for k, v in parts.items()},
    }


# ---------------------------------------------------------------------------
# Renderers
# ---------------------------------------------------------------------------
def render_outputs(out_dir, orig_img, L, S, regions, hotspots, findings,
                   scale, blur=None):
    os.makedirs(out_dir, exist_ok=True)
    paths = {}

    gray8 = np.clip(L / 100.0 * 255.0, 0, 255).astype(np.uint8)
    p = os.path.join(out_dir, "gray.png")
    Image.fromarray(gray8, "L").save(p)
    paths["gray"] = p

    if blur is not None:
        for key in ("color_heavy", "color_extreme"):
            p = os.path.join(out_dir, f"blur_{key}.png")
            Image.fromarray(blur[key], "RGB").save(p)
            paths[f"blur_{key}"] = p
        for key in ("gray_heavy", "gray_extreme"):
            p = os.path.join(out_dir, f"blur_{key}.png")
            Image.fromarray(blur[key], "L").save(p)
            paths[f"blur_{key}"] = p

    # bands: posterized L* + legend strip with band shares
    band_idx = np.clip(np.digitize(L, BAND_EDGES[1:-1]), 0, 4)
    centers = [(BAND_EDGES[i] + BAND_EDGES[i + 1]) / 2 for i in range(5)]
    band_gray = np.array([int(c / 100 * 255) for c in centers],
                         dtype=np.uint8)[band_idx]
    h, w = band_gray.shape
    legend_h = max(22, h // 18)
    canvas = Image.new("L", (w, h + legend_h), 0)
    canvas.paste(Image.fromarray(band_gray, "L"), (0, 0))
    draw = ImageDraw.Draw(canvas)
    font = load_font(max(11, legend_h - 8))
    shares = [float((band_idx == i).mean()) for i in range(5)]
    seg = w / 5
    for i in range(5):
        x0 = int(i * seg)
        draw.rectangle([x0, h, int((i + 1) * seg), h + legend_h],
                       fill=int(centers[i] / 100 * 255))
        txt = f"{BAND_EDGES[i]}-{BAND_EDGES[i + 1]}: {shares[i] * 100:.0f}%"
        draw.text((x0 + 4, h + 3), txt, font=font,
                  fill=255 if centers[i] < 50 else 0)
    p = os.path.join(out_dir, "bands.png")
    canvas.save(p)
    paths["bands"] = p
    band_shares = shares

    heat = colormap_inferno(S)
    p = os.path.join(out_dir, "saliency.png")
    Image.fromarray(heat, "RGB").save(p)
    paths["saliency"] = p

    base = np.stack([gray8] * 3, axis=-1).astype(np.float32) * 0.35
    alpha = (0.15 + 0.85 * S)[..., None]
    over = np.clip(base * (1 - alpha) + heat.astype(np.float32) * alpha,
                   0, 255).astype(np.uint8)
    p = os.path.join(out_dir, "saliency_overlay.png")
    Image.fromarray(over, "RGB").save(p)
    paths["saliency_overlay"] = p

    # hotspots on the original
    img = orig_img.convert("RGB")
    dim = Image.eval(img, lambda v: int(v * 0.55))
    draw = ImageDraw.Draw(dim)
    fpx = max(13, img.size[0] // 70)
    font = load_font(fpx)
    for s in hotspots:
        x, y, bw, bh = s["bbox"]
        draw.rectangle([x, y, x + bw, y + bh], outline=(255, 80, 80),
                       width=max(2, fpx // 6))
        draw_label(draw, (x + 3, max(0, y - fpx - 6)),
                   f"#{s['rank']}  {s['mass_share'] * 100:.0f}%",
                   font, fg=(255, 255, 255), bg=(180, 30, 30))
    p = os.path.join(out_dir, "hotspots.png")
    dim.save(p)
    paths["hotspots"] = p

    # annotated regions on the original
    if regions:
        img2 = Image.eval(img, lambda v: int(v * 0.82))
        draw = ImageDraw.Draw(img2)
        crit = {f["region"] for f in findings if f["severity"] == "CRITICAL"}
        for r in sorted(regions, key=lambda r: -(r["rect"][2] * r["rect"][3])):
            x, y, rw, rh = r["rect"]
            lvl = r["level"]
            color = ((120, 120, 120) if r["ignore"]
                     else LEVEL_COLORS.get(lvl, (200, 200, 200)))
            width = max(2, fpx // 6)
            if r["name"] in crit:
                draw.rectangle([x - 2, y - 2, x + rw + 2, y + rh + 2],
                               outline=(255, 40, 40), width=width + 2)
            draw.rectangle([x, y, x + rw, y + rh], outline=color, width=width)
            if r["ignore"]:
                tag = f"{r['name']} (ignored)"
            else:
                m = r["metrics"]
                tag = (f"{r['name']}  L{lvl} -> #{m['attention_rank']}  "
                       f"dL{m['dl_surround']:+.0f}")
            draw_label(draw, (x + 3, y + 3), tag, font,
                       fg=(0, 0, 0), bg=color)
        p = os.path.join(out_dir, "annotated.png")
        img2.save(p)
        paths["annotated"] = p

    return paths, band_shares


# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------
def write_reports(out_dir, image_path, regions, hotspots, findings, score,
                  band_shares, warnings, paths, th=None):
    th = th or DEFAULT_THRESHOLDS
    rep = {
        "image": os.path.abspath(image_path),
        "score": score,
        "band_shares": {f"{BAND_EDGES[i]}-{BAND_EDGES[i + 1]}":
                        round(band_shares[i], 3) for i in range(5)},
        "hotspots": hotspots,
        "regions": [{k: v for k, v in r.items()} for r in regions],
        "findings": findings,
        "warnings": warnings,
        "outputs": {k: os.path.abspath(v) for k, v in paths.items()},
    }
    jp = os.path.join(out_dir, "report.json")
    with open(jp, "w", encoding="utf-8") as f:
        json.dump(rep, f, indent=1, default=float)

    lines = []
    lines.append(f"# Tonal hierarchy report — {os.path.basename(image_path)}")
    lines.append("")
    if score and score.get("score") is not None:
        lines.append(f"**Hierarchy score: {score['score']}/100**")
        for k, v in score["parts"].items():
            lines.append(f"- {k}: {v['got']}/{v['max']}")
    else:
        lines.append("**No score** (need >= 2 leveled regions).")
    lines.append("")
    n_crit = sum(1 for f in findings if f["severity"] == "CRITICAL")
    n_warn = sum(1 for f in findings if f["severity"] == "WARN")
    lines.append(f"Findings: {n_crit} CRITICAL, {n_warn} WARN, "
                 f"{len(findings) - n_crit - n_warn} INFO")
    lines.append("")
    if findings:
        lines.append("## Findings")
        for f_ in findings:
            lines.append(f"- **[{f_['severity']}] {f_['code']}** — "
                         f"{f_['message']}")
            lines.append(f"  - Fix: {f_['fix']}")
        lines.append("")
    if hotspots:
        lines.append("## Attention hotspots (where the eye goes first)")
        lines.append("| # | mass | at | inside region |")
        lines.append("|---|------|----|---------------|")
        for s in hotspots:
            host = s.get("host")
            lines.append(
                f"| {s['rank']} | {s['mass_share'] * 100:.0f}% | "
                f"({s['centroid'][0]:.0f}, {s['centroid'][1]:.0f}) | "
                f"{host or '—'} |")
        lines.append("")
    live = [r for r in regions if not r["ignore"]]
    if live:
        lines.append("## Regions (rank #1 = most attention; blur = what "
                     "survives the squint test)")
        lines.append("| region | level | role | rank | mean L* | dL* vs "
                     "surround | sal share | internal std | blur dL* | "
                     "blur chroma | squint |")
        lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
        for r in sorted(live, key=lambda r: r["metrics"]["attention_rank"]):
            m = r["metrics"]
            has_blur = "dl_blur" in m
            # same thresholds as the blur-invisible finding — the squint
            # column and the findings must never disagree
            survives = has_blur and (abs(m["dl_blur"]) >= th["blur_dl"]
                                     or m["chroma_blur"] >= th["blur_chroma"])
            lines.append(
                f"| {r['name']} | {r['level']} | {r['role'] or ''} | "
                f"#{m['attention_rank']} | {m['mean_l']:.0f} | "
                f"{m['dl_surround']:+.0f} | {m['sal_share'] * 100:.0f}% | "
                f"{m['std_l']:.0f} | "
                f"{m['dl_blur']:+.0f} | {m['chroma_blur']:.0f} | "
                f"{'VISIBLE' if survives else 'GONE'} |"
                if has_blur else
                f"| {r['name']} | {r['level']} | {r['role'] or ''} | "
                f"#{m['attention_rank']} | {m['mean_l']:.0f} | "
                f"{m['dl_surround']:+.0f} | {m['sal_share'] * 100:.0f}% | "
                f"{m['std_l']:.0f} | — | — | — |")
        lines.append("")
    lines.append("## Value bands (share of image per L* band)")
    lines.append("| " + " | ".join(
        f"{BAND_EDGES[i]}-{BAND_EDGES[i + 1]}" for i in range(5)) + " |")
    lines.append("|" + "---|" * 5)
    lines.append("| " + " | ".join(
        f"{band_shares[i] * 100:.0f}%" for i in range(5)) + " |")
    lines.append("")
    lines.append("## Files")
    for k, v in paths.items():
        lines.append(f"- {k}: `{os.path.basename(v)}`")
    if warnings:
        lines.append("")
        lines.append("## Warnings")
        for w_ in warnings:
            lines.append(f"- {w_}")
    mp = os.path.join(out_dir, "report.md")
    with open(mp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return jp, mp


# ---------------------------------------------------------------------------
# Analysis driver
# ---------------------------------------------------------------------------
def load_image_rgb(image_path):
    """Open + composite transparency over mid-gray + downscale to the
    working resolution. ONE loader for every subcommand, so blur/analyze
    can never disagree about what the image looks like."""
    img = Image.open(image_path)
    if img.mode in ("RGBA", "LA", "P"):
        img = img.convert("RGBA")
        bg = Image.new("RGBA", img.size, (127, 127, 127, 255))
        img = Image.alpha_composite(bg, img)
    img = img.convert("RGB")
    W, H = img.size
    scale = min(1.0, WORK_MAX_DIM / max(W, H))
    work = (img if scale >= 0.999 else
            img.resize((max(1, int(W * scale)), max(1, int(H * scale))),
                       Image.LANCZOS))
    return img, work, W, H, scale


def analyze_image(image_path, regions_path=None, out_dir=None,
                  thresholds=None, quiet=False):
    th = dict(DEFAULT_THRESHOLDS)
    if thresholds:
        th.update(thresholds)
    img, work, W, H, scale = load_image_rgb(image_path)
    arr = np.asarray(work, dtype=np.float32) / 255.0
    L, a, b, ylin = rgb_to_lab(arr)
    S = compute_saliency(L, a, b)
    blur = compute_blur_maps(arr, L, a, b)

    warnings = []
    regions = []
    if regions_path:
        regions, warnings = load_regions(regions_path, (W, H))
        eff_scale = work.size[0] / W
        regions = region_metrics(regions, L, S, ylin, eff_scale, blur)

    inv_scale = W / work.size[0]
    hotspots = extract_hotspots(S, th["hotspot_pctl"],
                                th["hotspot_min_frac"], inv_scale)
    for s in hotspots:
        host = hotspot_region(s, regions)
        s["host"] = host["name"] if host else None

    findings = build_findings(regions, hotspots, th) if regions else []
    score = hierarchy_score(regions, th) if regions else None

    if out_dir is None:
        stem = os.path.splitext(os.path.basename(image_path))[0]
        out_dir = os.path.join(os.path.dirname(os.path.abspath(image_path)),
                               stem + "_tonal")
    paths, band_shares = render_outputs(out_dir, img, L, S, regions, hotspots,
                                        findings, scale, blur)
    jp, mp = write_reports(out_dir, image_path, regions, hotspots, findings,
                           score, band_shares, warnings, paths, th)

    if not quiet:
        print(f"[tonal] analyzed {image_path} ({W}x{H})")
        if score and score.get("score") is not None:
            print(f"[tonal] hierarchy score: {score['score']}/100")
        for f_ in findings:
            print(f"[tonal]  {f_['severity']:8s} {f_['code']}: "
                  f"{f_['message']}")
        if not regions:
            print("[tonal] no regions given - saliency/hotspots only "
                  "(pass --regions for findings + score)")
        for w_ in warnings:
            print(f"[tonal]  note: {w_}")
        print(f"[tonal] report: {mp}")
    return {"score": score, "findings": findings, "regions": regions,
            "hotspots": hotspots, "out_dir": out_dir, "report_md": mp,
            "report_json": jp}


# ---------------------------------------------------------------------------
# Compare
# ---------------------------------------------------------------------------
def cmd_compare(args):
    th = load_config(args.config)
    out = args.out or (os.path.splitext(args.after)[0] + "_compare")
    before = analyze_image(args.before, args.regions,
                           os.path.join(out, "before"), th, quiet=True)
    after = analyze_image(args.after, args.regions_after or args.regions,
                          os.path.join(out, "after"), th, quiet=True)

    def crit(res):
        return sum(1 for f in res["findings"] if f["severity"] == "CRITICAL")

    sb = (before["score"] or {}).get("score")
    sa = (after["score"] or {}).get("score")
    lines = ["# Tonal compare", "",
             f"| | before | after |", "|---|---|---|",
             f"| score | {sb} | {sa} |",
             f"| CRITICAL | {crit(before)} | {crit(after)} |",
             f"| WARN | {sum(1 for f in before['findings'] if f['severity'] == 'WARN')} "
             f"| {sum(1 for f in after['findings'] if f['severity'] == 'WARN')} |",
             ""]
    before_keys = {(f["code"], f.get("region")) for f in before["findings"]
                   if f["severity"] == "CRITICAL"}
    after_keys = {(f["code"], f.get("region")) for f in after["findings"]
                  if f["severity"] == "CRITICAL"}
    new_crits = after_keys - before_keys
    if sb is not None and sa is not None:
        delta = sa - sb
        # Clearing CRITICAL violations without introducing new ones IS the
        # improvement this tool drives — the structure score is a trend
        # indicator, the findings are the gate.
        if crit(after) > crit(before) or (delta <= -3 and new_crits):
            verdict = "REGRESSED"
        elif not new_crits and (crit(after) < crit(before) or delta >= 3):
            verdict = "IMPROVED"
        elif delta <= -3:
            verdict = "REGRESSED"
        else:
            verdict = "FLAT"
    else:
        verdict = "NO-SCORE"
        delta = None
    lines.append(f"**Verdict: {verdict}**" +
                 (f" (score {sb} -> {sa}, {delta:+.1f})"
                  if delta is not None else ""))
    lines.append("")
    def actionable(res):
        return [f for f in res["findings"] if f["severity"] != "INFO"]

    fixed = [f["code"] + ":" + str(f.get("region"))
             for f in actionable(before)
             if (f["code"], f.get("region")) not in
             {(g["code"], g.get("region")) for g in actionable(after)}]
    intro = [f["code"] + ":" + str(f.get("region"))
             for f in actionable(after)
             if (f["code"], f.get("region")) not in
             {(g["code"], g.get("region")) for g in actionable(before)}]
    if fixed:
        lines.append("Resolved: " + ", ".join(fixed))
    if intro:
        lines.append("Introduced: " + ", ".join(intro))
    os.makedirs(out, exist_ok=True)
    cp = os.path.join(out, "compare.md")
    with open(cp, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print("\n".join(lines))
    print(f"[tonal] compare report: {cp}")
    return 0


# ---------------------------------------------------------------------------
# Listen (one-shot HTTP receiver for regions dumped from Roblox Studio)
# ---------------------------------------------------------------------------
def cmd_listen(args):
    from http.server import BaseHTTPRequestHandler, HTTPServer
    out_path = args.out
    received = {}

    class H(BaseHTTPRequestHandler):
        def do_POST(self):
            n = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(n)
            try:
                json.loads(body.decode("utf-8"))
            except (ValueError, UnicodeDecodeError) as e:
                print(f"[tonal] rejected POST: not valid JSON ({e})")
                self.send_response(400)
                self.end_headers()
                self.wfile.write(b"invalid json")
                return
            with open(out_path, "wb") as f:
                f.write(body)
            received["ok"] = True
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, *a):
            pass

    srv = HTTPServer(("127.0.0.1", args.port), H)
    print(f"[tonal] waiting for POST on 127.0.0.1:{args.port} "
          f"(timeout {args.timeout}s)...")
    deadline = args.timeout
    import time
    t0 = time.time()
    while not received.get("ok") and time.time() - t0 < deadline:
        srv.timeout = max(1.0, deadline - (time.time() - t0))
        srv.handle_request()
    if received.get("ok"):
        print(f"[tonal] regions written to {out_path}")
        return 0
    print("[tonal] timed out - nothing received")
    return 1


# ---------------------------------------------------------------------------
# Selftest
# ---------------------------------------------------------------------------
def _fixture(kind):
    """600x400 mock 'shop panel'. kind = 'bad' | 'good'."""
    img = Image.new("RGB", (600, 400), (205, 208, 214))
    d = ImageDraw.Draw(img)
    if kind == "bad":
        tabs = [(214, 216, 222), (72, 78, 96), (72, 78, 96), (72, 78, 96)]
        cta = (176, 178, 186)          # dull, blends in
        patch = (255, 200, 0)           # loud yellow decor
        chip = (198, 201, 208)          # mushy chips
    else:
        tabs = [(94, 118, 168), (188, 192, 202), (188, 192, 202),
                (188, 192, 202)]
        cta = (32, 150, 70)             # saturated dark green CTA
        patch = (214, 208, 190)         # quiet decor
        chip = (168, 172, 182)          # separated chips
    for i, c in enumerate(tabs):        # left tab column
        d.rectangle([20, 24 + i * 66, 140, 24 + i * 66 + 52], fill=c)
    d.rectangle([170, 40, 560, 340], fill=(226, 228, 233))   # card
    d.rectangle([190, 70, 310, 160], fill=patch)             # art / decor
    for i in range(3):                                       # chips
        d.rectangle([330 + i * 78, 90, 330 + i * 78 + 64, 130], fill=chip)
    d.rectangle([330, 250, 520, 310], fill=cta)              # buy button
    return img


_FIXTURE_REGIONS = {
    "regions": [
        {"name": "buy-button", "rect": [330, 250, 190, 60], "level": 1,
         "role": "cta"},
        {"name": "active-tab", "rect": [20, 24, 120, 52], "level": 2,
         "role": "tab-active"},
        {"name": "inactive-tab-1", "rect": [20, 90, 120, 52], "level": 3,
         "role": "tab-inactive"},
        {"name": "inactive-tab-2", "rect": [20, 156, 120, 52], "level": 3,
         "role": "tab-inactive"},
        {"name": "art-decor", "rect": [190, 70, 120, 90], "level": 3,
         "role": "decor"},
        {"name": "chips", "rect": [330, 90, 220, 40], "level": 3,
         "role": "content"},
        {"name": "card-body", "rect": [170, 40, 390, 300], "level": 4,
         "role": "container"},
        {"name": "panel-bg", "rect": [0, 0, 600, 400], "level": 4,
         "role": "background"},
    ]
}


def cmd_selftest(args):
    keep = args.keep
    root = keep or tempfile.mkdtemp(prefix="tonal_selftest_")
    os.makedirs(root, exist_ok=True)
    passed, failed = [], []

    def check(name, ok, detail=""):
        (passed if ok else failed).append(name)
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}"
              + (f" - {detail}" if detail and not ok else ""))

    print("[tonal] selftest ...")

    # 1. L* math sanity
    probe = np.array([[[1.0, 1.0, 1.0], [0.0, 0.0, 0.0],
                       [118 / 255.0] * 3]], dtype=np.float32)
    L, _, _, _ = rgb_to_lab(probe)
    check("L* of white ~ 100", abs(float(L[0, 0]) - 100) < 0.6,
          f"got {float(L[0, 0]):.2f}")
    check("L* of black ~ 0", abs(float(L[0, 1])) < 0.6,
          f"got {float(L[0, 1]):.2f}")
    check("L* of 18% gray (118,118,118) ~ 49.5",
          abs(float(L[0, 2]) - 49.5) < 1.5, f"got {float(L[0, 2]):.2f}")

    # 2. component labeling
    m = np.zeros((20, 40), dtype=bool)
    m[2:6, 2:8] = True
    m[12:18, 25:38] = True
    labs = label_components(m)
    check("labeling finds 2 blobs", int(labs.max()) == 2,
          f"got {int(labs.max())}")

    # 3. fixtures
    rj = os.path.join(root, "regions.json")
    with open(rj, "w", encoding="utf-8") as f:
        json.dump(_FIXTURE_REGIONS, f)
    imgs = {}
    for kind in ("bad", "good"):
        p = os.path.join(root, f"{kind}.png")
        _fixture(kind).save(p)
        imgs[kind] = p
    bad = analyze_image(imgs["bad"], rj, os.path.join(root, "bad_out"),
                        quiet=True)
    good = analyze_image(imgs["good"], rj, os.path.join(root, "good_out"),
                         quiet=True)

    bad_codes = {f["code"] for f in bad["findings"]}
    good_crit = [f for f in good["findings"] if f["severity"] == "CRITICAL"]
    check("bad fixture: flat-primary fires", "flat-primary" in bad_codes,
          str(bad_codes))
    check("bad fixture: inverted-hierarchy fires",
          "inverted-hierarchy" in bad_codes, str(bad_codes))
    check("bad fixture: decor flagged (sink or stray)",
          bool({"attention-sink", "stray-hotspot"} & bad_codes),
          str(bad_codes))
    check("good fixture: no CRITICAL findings", not good_crit,
          str([f["code"] for f in good_crit]))
    sb = bad["score"]["score"]
    sg = good["score"]["score"]
    check(f"good score ({sg}) > bad score ({sb}) by >= 15", sg - sb >= 15)
    check(f"good score >= 70 (got {sg})", sg >= 70)
    check(f"bad score <= 55 (got {sb})", sb <= 55)
    g_cta = next(r for r in good["regions"] if r["name"] == "buy-button")
    check("good fixture: CTA is attention rank #1",
          g_cta["metrics"]["attention_rank"] == 1,
          f"rank {g_cta['metrics']['attention_rank']}")
    gm = g_cta["metrics"]
    check("blur metrics computed", "dl_blur" in gm and "chroma_blur" in gm)
    check("good fixture: CTA survives the squint test",
          abs(gm.get("dl_blur", 0)) >= 8 or gm.get("chroma_blur", 0) >= 10,
          f"dl_blur {gm.get('dl_blur')}, chroma {gm.get('chroma_blur')}")
    check("blur images written",
          os.path.exists(os.path.join(root, "good_out", "blur_color_heavy.png"))
          and os.path.exists(os.path.join(root, "good_out",
                                          "blur_gray_extreme.png")))

    # 4. compare verdict
    import io
    from contextlib import redirect_stdout
    ns = argparse.Namespace(before=imgs["bad"], after=imgs["good"],
                            regions=rj, regions_after=None,
                            out=os.path.join(root, "cmp"), config=None)
    buf = io.StringIO()
    with redirect_stdout(buf):
        cmd_compare(ns)
    check("compare(bad -> good) = IMPROVED", "IMPROVED" in buf.getvalue())

    print(f"[tonal] selftest: {len(passed)} passed, {len(failed)} failed"
          + (f" (outputs kept in {root})" if keep else ""))
    if failed:
        print("[tonal] FAILED: " + ", ".join(failed))
        return 1
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def load_config(path):
    if not path:
        return None
    with open(path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def main(argv=None):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    ap = argparse.ArgumentParser(
        prog="tonal.py", description="UI tonal-hierarchy analyzer")
    sub = ap.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("analyze", help="analyze one screenshot")
    a.add_argument("image")
    a.add_argument("--regions", help="regions JSON (see module docstring)")
    a.add_argument("--out", help="output directory "
                                 "(default <image>_tonal/)")
    a.add_argument("--config", help="JSON overriding threshold defaults")

    c = sub.add_parser("compare", help="before/after comparison")
    c.add_argument("before")
    c.add_argument("after")
    c.add_argument("--regions", help="regions JSON for both")
    c.add_argument("--regions-after", help="regions JSON for AFTER if the "
                                           "layout moved")
    c.add_argument("--out")
    c.add_argument("--config")

    bl = sub.add_parser("blur", help="squint test only: heavy blur images "
                                     "(gray + color, two strengths)")
    bl.add_argument("image")
    bl.add_argument("--out", help="output directory (default <image>_tonal/)")

    t = sub.add_parser("selftest", help="run built-in fixtures")
    t.add_argument("--keep", help="directory to keep fixture outputs in")

    l = sub.add_parser("listen", help="one-shot HTTP receiver for regions "
                                      "dumped from Roblox Studio")
    l.add_argument("--port", type=int, default=8788)
    l.add_argument("--out", default="regions.json")
    l.add_argument("--timeout", type=int, default=120)

    args = ap.parse_args(argv)
    if args.cmd == "analyze":
        analyze_image(args.image, args.regions, args.out,
                      load_config(args.config))
        return 0
    if args.cmd == "blur":
        _, work, _, _, _ = load_image_rgb(args.image)
        arr = np.asarray(work, dtype=np.float32) / 255.0
        L, a, b, _ = rgb_to_lab(arr)
        blur = compute_blur_maps(arr, L, a, b)
        stem = os.path.splitext(os.path.basename(args.image))[0]
        out = args.out or os.path.join(
            os.path.dirname(os.path.abspath(args.image)), stem + "_tonal")
        os.makedirs(out, exist_ok=True)
        for key in ("color_heavy", "color_extreme"):
            Image.fromarray(blur[key], "RGB").save(
                os.path.join(out, f"blur_{key}.png"))
        for key in ("gray_heavy", "gray_extreme"):
            Image.fromarray(blur[key], "L").save(
                os.path.join(out, f"blur_{key}.png"))
        print(f"[tonal] squint-test images written to {out}")
        return 0
    if args.cmd == "compare":
        return cmd_compare(args)
    if args.cmd == "selftest":
        return cmd_selftest(args)
    if args.cmd == "listen":
        return cmd_listen(args)
    return 2


if __name__ == "__main__":
    sys.exit(main())
