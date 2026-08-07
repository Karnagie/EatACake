#!/usr/bin/env python3
"""Cake pacing + PROGRESSION model — how long is a run, and when is the tree maxed?

WHY THIS EXISTS
---------------
`tools/headless-sim/` already runs the REAL modules and is the authority on bite
math. It answers a narrower question: it measures the two ENDPOINTS of the upgrade
curve (a tier-0 eater, a maxed eater) and reports each as a separate full cake.
(It also needed the standalone Luau CLI, which was not installed when this file was
written. It IS installed now, so the two tools can and should be cross-checked.)

The 2026-07-30 rebalance needs the thing BETWEEN those endpoints: one run in
which the player earns calories, BUYS TIERS MID-RUN, and gets faster as they go.
That is what decides both numbers the design targets:

    * total clear time (target ~40 min, solo easy)
    * the % of the cake eaten by the time every tier is owned (target <= 50%)

Neither is derivable from the endpoint measurements: a tier-0 eater and a maxed
eater say nothing about where a RAMPING player lands, and since ADR-0019 the
tier-0 endpoint is not even a plausible session (capacity base is sized for the
first ~10 s of a run). Usage below; `--intervals` is the ADR-0019 curve.

FIDELITY
--------
This is a PORT, so it can drift. Two guards:
  1. `check_config_sync()` re-reads the real Lua configs and fails loudly if any
     mirrored constant no longer matches. Run it every time (it is automatic).
  2. `validate()` prints the two ENDPOINTS so they can be reconciled against
     tools/headless-sim section B, which runs the real Lua modules. ⚠ Since
     ADR-0019 the tier-0 endpoint is not a session estimate at all (`capacity`
     base is sized for the first ~10 s of a run), so treat it as a bound on the
     BITE MATH only; the number a player lives through is `report()` below.
     If the two tools diverge, distrust whichever one you have not just changed —
     the 2026-08-05 pass found the bug in THIS file, not in the game.

What is modelled: RollComposition, CakeOps.ApplyBite, the layer gate, the sliver
+ remnant sweeps (both forfeiting, both capped by sweepBandFraction), per-band
density -> food, per-layer calories/hardness, the belly->gym cycle, and a
tier-buying player.
What is NOT: the settle automaton (it only reshapes the cut edge), walking
between craters, boss/reveal/spawn time, pets, passes, rare cakes.

Usage:
    python tools/balance-model/pacing.py             # validate + report the live config
    python tools/balance-model/pacing.py --intervals # seconds per belly, by capacity tier
    python tools/balance-model/pacing.py --solve     # search for a tuning that hits the targets
"""
from __future__ import annotations

import argparse
import math
import os
import random
import re
import sys
from dataclasses import dataclass, field, replace

import numpy as np

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
UNITS_PER_STUD = 100


# ── mirrored constants ───────────────────────────────────────────────────────
# Every value here is checked against the real Lua config by check_config_sync().

GRID = dict(size=64, cell=1.5, origin_x=0.0, origin_z=0.0)

COMP = dict(
    # ROUND cake since 2026-08-03: hx == hz == corner IS the circle (the Lua
    # InCake is a rounded-rect SDF). Keep all three equal when syncing.
    footprint_hx=31.1, footprint_hz=31.1, footprint_corner=31.1,
    core_thickness=3,
    base_layers=28, max_layers=42,
    max_total_height=170.0,
    min_layer_thickness=3.5,
    thickness_exponent=0.6,
    scoop_top=2.23, scoop_bottom=0.558,
    ref_band_weight=25.4, max_density=12.0,
    coop_work=0.5, layer_exponent=0.55, coop_calories=0.62,
)

# MatchConfig difficulty work multipliers (the cake's WORK lever, ADR-0011) and
# the payout premium that rides with them (it scales `calories_mult`).
MATCH_WORK = dict(easy=1.08, medium=1.27, hard=1.49)
MATCH_CALORIES = dict(easy=1.0, medium=1.25, hard=1.55)

SIM = dict(
    min_bite_radius=1.1,
    bite_clear_ref_depth=3.6,
    sliver_sweep_studs=1.5,
    sweep_band_fraction=0.25,
    remnant_cleared_margin=2.0,
    remnant_near_floor=2.5,
    remnant_min_cleared_neighbors=3,
)

# id -> (hardness, calories). `frosting` is always the top band; the rest are the
# middlePool that layer identity is rolled from.
LAYERS = {
    'frosting':  (0.85, 0.139),
    'sponge':    (1.00, 0.155),
    'chocolate': (1.25, 0.237),
    'jelly':     (1.08, 0.188),
    'cotton':    (0.85, 0.122),
    'caramel':   (1.15, 0.204),
    'crumb':     (0.95, 0.147),
    'filling':   (0.90, 0.163),
    'core':      (math.inf, 0.0),
}
MIDDLE_POOL = ['sponge', 'chocolate', 'jelly', 'cotton', 'caramel', 'crumb', 'filling']


@dataclass
class Upgrade:
    base: float
    values: list
    costs: list

    def value(self, tier: int) -> float:
        if tier <= 0:
            return self.base
        return self.values[min(tier, len(self.values)) - 1]


def live_upgrades() -> dict:
    """UpgradeConfig tiers, mirrored (checked by check_config_sync)."""
    return {
        'capacity':    Upgrade(4400, [13000, 58000, 120000, 235000, 645000],
                               [400, 1350, 4600, 15500, 53000]),
        'runSpeed':    Upgrade(20, [23, 26, 29, 32, 35],
                               [300, 1000, 3400, 11500, 39000]),
        'biteRadius':  Upgrade(2.4, [2.65, 2.9, 3.2, 4.5, 5.8],
                               [450, 1550, 5250, 17800, 60500]),
        'biteDepth':   Upgrade(2.6, [3.1, 3.6, 4.1, 5.6, 6.2],
                               [440, 1500, 5100, 17300, 58800]),
        'eatSpeed':    Upgrade(4, [4.4, 4.75, 5.05, 5.3, 5.6],
                               [390, 1300, 4400, 15000, 51000]),
        'gymEff':      Upgrade(1, [1.2, 1.45, 1.7, 2.0, 2.35],
                               [550, 1850, 6300, 21400, 72800]),
        'burnSpeed':   Upgrade(0.20, [0.28, 0.40, 0.58, 0.85, 1.25],
                               [280, 950, 3200, 10900, 37000]),
        'burnPerTap':  Upgrade(0.10, [0.14, 0.20, 0.30, 0.45, 0.70],
                               [250, 850, 2900, 9800, 33300]),
        'instantBurn': Upgrade(0, [0.20, 0.45, 0.70, 1.00],
                               [3300, 11200, 38100, 129500]),
    }


# ── config drift guard ───────────────────────────────────────────────────────

def _lua(path: str) -> str:
    with open(os.path.join(REPO, path), encoding='utf-8') as handle:
        return handle.read()


def _num(src: str, key: str):
    """First `key = <number>` in the source (comments included -- fine, keys are unique)."""
    m = re.search(re.escape(key) + r'\s*=\s*(-?[0-9.]+)', src)
    return float(m.group(1)) if m else None


def check_config_sync() -> list:
    """Compare every mirrored constant with the real Lua config. Empty == in sync."""
    problems = []
    cake = _lua('src/shared/config/CakeConfig.lua')
    upg = _lua('src/shared/config/UpgradeConfig.lua')

    def cmp(label, got, want):
        if got is None:
            problems.append('%s: not found in the Lua config (renamed?)' % label)
        elif abs(got - want) > 1e-9:
            problems.append('%s: Lua has %g, model has %g' % (label, got, want))

    cmp('grid.size', _num(cake, 'size'), GRID['size'])
    cmp('grid.cell', _num(cake, 'cell'), GRID['cell'])
    for key, want in (('baseLayers', COMP['base_layers']), ('maxLayers', COMP['max_layers']),
                      ('maxTotalHeight', COMP['max_total_height']),
                      ('minLayerThickness', COMP['min_layer_thickness']),
                      ('thicknessExponent', COMP['thickness_exponent']),
                      ('scoopTop', COMP['scoop_top']), ('scoopBottom', COMP['scoop_bottom']),
                      ('refBandWeight', COMP['ref_band_weight']),
                      ('maxDensity', COMP['max_density']),
                      ('coopWork', COMP['coop_work']), ('layerExponent', COMP['layer_exponent']),
                      ('coopCalories', COMP['coop_calories']),
                      ('coreThickness', COMP['core_thickness'])):
        cmp('composition.' + key, _num(cake, key), want)
    for key, want in (('minBiteRadiusStuds', SIM['min_bite_radius']),
                      ('biteClearRefDepth', SIM['bite_clear_ref_depth']),
                      ('sliverSweepStuds', SIM['sliver_sweep_studs']),
                      ('sweepBandFraction', SIM['sweep_band_fraction']),
                      ('clearedMarginStuds', SIM['remnant_cleared_margin']),
                      ('nearFloorStuds', SIM['remnant_near_floor']),
                      ('minClearedNeighbors', SIM['remnant_min_cleared_neighbors'])):
        cmp('sim.' + key, _num(cake, key), want)

    # Difficulty work multipliers live in MatchConfig, not CakeConfig.
    match = _lua('src/shared/config/MatchConfig.lua')
    for mode, want in MATCH_WORK.items():
        block = re.search(r'\n\t%s\s*=\s*{(.*?)\n\t},' % mode, match, re.S)
        if not block:
            problems.append('difficulties.%s: not found in MatchConfig' % mode)
            continue
        cmp('difficulties.%s.workMultiplier' % mode, _num(block.group(1), 'workMultiplier'), want)

    # Footprint lives in one inline table.
    m = re.search(r'footprint\s*=\s*{\s*hx\s*=\s*([0-9.]+),\s*hz\s*=\s*([0-9.]+),\s*corner\s*=\s*([0-9.]+)', cake)
    if not m:
        problems.append('composition.footprint: not found')
    else:
        cmp('footprint.hx', float(m.group(1)), COMP['footprint_hx'])
        cmp('footprint.hz', float(m.group(2)), COMP['footprint_hz'])
        cmp('footprint.corner', float(m.group(3)), COMP['footprint_corner'])

    # Per-layer hardness/calories.
    for name, (hardness, calories) in LAYERS.items():
        block = re.search(r'\n\t%s\s*=\s*{(.*?)\n\t},' % name, cake, re.S)
        if not block:
            problems.append('layers.%s: not found' % name)
            continue
        body = block.group(1)
        got_h, got_c = _num(body, 'hardness'), _num(body, 'calories')
        if math.isinf(hardness):
            if 'math.huge' not in body:
                problems.append('layers.%s.hardness: expected math.huge' % name)
        else:
            cmp('layers.%s.hardness' % name, got_h, hardness)
        cmp('layers.%s.calories' % name, got_c, calories)

    # Upgrade tiers: values and costs, in order, per stat.
    for stat, up in live_upgrades().items():
        block = re.search(r'\b%s\s*=\s*{\s*\n\s*id\s*=\s*"%s"(.*?)\n\t\t},\n' % (stat, stat), upg, re.S)
        if not block:
            problems.append('upgrades.%s: not found' % stat)
            continue
        body = block.group(1)
        base = _num(body, 'base')
        cmp('upgrades.%s.base' % stat, base, up.base)
        pairs = re.findall(r'{\s*value\s*=\s*([0-9.]+),\s*cost\s*=\s*([0-9]+)\s*}', body)
        if len(pairs) != len(up.values):
            problems.append('upgrades.%s: Lua has %d tiers, model has %d'
                            % (stat, len(pairs), len(up.values)))
            continue
        for i, (val, cost) in enumerate(pairs):
            cmp('upgrades.%s.tier%d.value' % (stat, i + 1), float(val), up.values[i])
            cmp('upgrades.%s.tier%d.cost' % (stat, i + 1), float(cost), up.costs[i])
    return problems


# ── geometry ─────────────────────────────────────────────────────────────────

def cake_mask(size, hx, hz, corner):
    """GridUtil.InCake over the whole grid. Indexed [z, x], matching i = z*size+x."""
    half = (size - 1) * 0.5
    x = np.arange(size)[None, :].astype(float)
    z = np.arange(size)[:, None].astype(float)
    ax, az = np.abs(x - half), np.abs(z - half)
    qx = np.maximum(ax - (hx - corner), 0.0)
    qz = np.maximum(az - (hz - corner), 0.0)
    return (qx * qx + qz * qz <= corner * corner) & (ax <= hx) & (az <= hz)


def cell_to_world(size, cell, ox, oz, x, z):
    half = size * 0.5
    return ox + (x - half + 0.5) * cell, oz + (z - half + 0.5) * cell


def studs_to_units(studs: float) -> int:
    return int(min(max(math.floor(studs * UNITS_PER_STUD + 0.5), 0), 65535))


# ── composition roll (CakeCycleService.RollComposition) ──────────────────────

@dataclass
class Band:
    layer: str
    bottom: float
    top: float
    scoop: float
    density: float

    @property
    def thickness(self):
        return self.top - self.bottom


def roll_composition(work: float, rng: random.Random, comp=COMP, jitter=True):
    layers = int(min(max(math.floor(comp['base_layers'] * work ** comp['layer_exponent'] + 0.5), 2),
                     comp['max_layers']))
    scoop_scale = (work / (layers / comp['base_layers'])) ** -0.5
    scoop_top = comp['scoop_top'] * scoop_scale
    scoop_bottom = comp['scoop_bottom'] * scoop_scale
    total_height = min(comp['max_total_height'], 340 - comp['core_thickness'])

    scoops, weights = [], []
    for k in range(layers):
        f = k / (layers - 1) if layers > 1 else 0.0
        scoop = scoop_top * (scoop_bottom / scoop_top) ** f
        scoops.append(scoop)
        weights.append((scoop_top / scoop) ** (2 * comp['thickness_exponent']))
    weight_sum = sum(weights)

    ids = ['frosting']
    last = 'frosting'
    for _ in range(1, layers):
        pick = last
        while pick == last:
            pick = MIDDLE_POOL[rng.randrange(len(MIDDLE_POOL))]
        last = pick
        ids.append(pick)

    thickness = []
    for k in range(layers):
        j = (0.9 + rng.random() * 0.2) if jitter else 1.0
        thickness.append(max(comp['min_layer_thickness'],
                             weights[k] / weight_sum * total_height * j))
    renorm = total_height / sum(thickness)
    thickness = [t * renorm for t in thickness]

    bands, cursor = [], 0.0
    bands.append(Band('core', 0.0, comp['core_thickness'], 1.0, 1.0))
    cursor = comp['core_thickness']
    for k in range(layers - 1, -1, -1):  # deepest designed band first (bottom-up)
        density = min(max(comp['ref_band_weight'] / (thickness[k] * scoops[k] ** 2), 1.0),
                      comp['max_density'])
        bands.append(Band(ids[k], cursor, cursor + thickness[k], scoops[k], density))
        cursor += thickness[k]
    return bands


# ── bite math (CakeOps.ApplyBite) ────────────────────────────────────────────

class Field:
    def __init__(self, bands, grid=GRID, comp=COMP):
        self.size = grid['size']
        self.cell = grid['cell']
        self.grid = grid
        self.bands = bands
        self.mask = cake_mask(self.size, comp['footprint_hx'], comp['footprint_hz'],
                              comp['footprint_corner'])
        top = bands[-1].top
        self.h = np.zeros((self.size, self.size), dtype=np.int64)
        self.h[self.mask] = studs_to_units(top)
        # Per-cell world coords, for the radius test.
        idx = np.arange(self.size).astype(float)
        half = self.size * 0.5
        self.wx = (grid['origin_x'] + (idx - half + 0.5) * self.cell)[None, :]
        self.wz = (grid['origin_z'] + (idx - half + 0.5) * self.cell)[:, None]
        # Band lookup by height: CakeOps.LayerAtStuds returns the first band whose
        # top >= h; above the last top it is the last band.
        self.band_tops = np.array([b.top for b in bands])
        self.hardness = np.array([LAYERS[b.layer][0] for b in bands])

    def hardness_at(self, h_units):
        studs = h_units / UNITS_PER_STUD
        idx = np.searchsorted(self.band_tops, studs, side='left')
        idx = np.minimum(idx, len(self.bands) - 1)
        return self.hardness[idx]

    def apply_bite(self, px, pz, radius, depth, floor_units, clear_ref):
        """Returns removed volume in studs^3 (CakeOps.ApplyBite, vectorised)."""
        size, cell = self.size, self.cell
        half = size * 0.5
        cx = int(math.floor((px - self.grid['origin_x']) / cell + half))
        cz = int(math.floor((pz - self.grid['origin_z']) / cell + half))
        r_cells = int(math.ceil(radius / cell))
        x0, x1 = max(cx - r_cells, 0), min(cx + r_cells, size - 1)
        z0, z1 = max(cz - r_cells, 0), min(cz + r_cells, size - 1)
        if x0 > x1 or z0 > z1:
            return 0.0

        sub_h = self.h[z0:z1 + 1, x0:x1 + 1]
        sub_mask = self.mask[z0:z1 + 1, x0:x1 + 1]
        dx = self.wx[:, x0:x1 + 1] - px
        dz = self.wz[z0:z1 + 1, :] - pz
        dist_sq = dx * dx + dz * dz

        inside = dist_sq <= radius * radius
        # ApplyBite always processes the cell the bite POINT sits in.
        if x0 <= cx <= x1 and z0 <= cz <= z1:
            inside = inside.copy()
            inside[cz - z0, cx - x0] = True

        falloff = 1.0 - dist_sq / (radius * radius)
        # The forced centre cell can fall outside the radius -> a small real bite.
        falloff = np.where(falloff <= 0, 0.15, falloff)

        hardness = self.hardness_at(sub_h)
        strength = (depth / clear_ref) if clear_ref > 0 else 1.0
        with np.errstate(divide='ignore', invalid='ignore'):
            clear_frac = np.clip(falloff * strength / hardness, 0.0, 1.0)
        clear_frac = np.where(np.isfinite(hardness), clear_frac, 0.0)  # chocolate/core: math.huge

        eligible = inside & sub_mask & (sub_h > floor_units)
        delta = np.floor((sub_h - floor_units) * clear_frac).astype(np.int64)
        delta = np.where(eligible & (delta > 0), delta, 0)
        # ⚠ The floor clamp must apply ONLY to cells this bite is allowed to touch.
        # Clamping the whole window (the pre-2026-08-05 code) RAISED every
        # out-of-cake cell in it from 0 to the band floor and counted the rise as
        # NEGATIVE removed volume — so every bite whose disc overlapped the rim
        # under-reported food, and the opening bites (argmax ties on a flat cake
        # resolve to the lowest index, i.e. the rim) reported food in the tens of
        # thousands NEGATIVE. Lua has no such bug: CakeOps.ApplyBite iterates the
        # cells it selected, one at a time.
        new_h = np.where(eligible, np.maximum(floor_units, sub_h - delta), sub_h)
        removed_units = int((sub_h - new_h).sum())
        self.h[z0:z1 + 1, x0:x1 + 1] = new_h
        return removed_units / UNITS_PER_STUD * cell * cell

    def sweeps(self, floor_units, band):
        """Sliver + remnant sweeps (CakeFieldService.ScanStats). Returns swept volume."""
        cap = SIM['sweep_band_fraction']
        def capped(studs):
            return min(studs, band.thickness * cap) if cap else studs

        swept_units = 0
        sliver_ceil = floor_units + studs_to_units(capped(SIM['sliver_sweep_studs']))
        sel = self.mask & (self.h > floor_units) & (self.h <= sliver_ceil)
        swept_units += int((self.h[sel] - floor_units).sum())
        self.h[sel] = floor_units

        cleared_ceil = floor_units + studs_to_units(SIM['remnant_cleared_margin'])
        near_floor = floor_units + studs_to_units(capped(SIM['remnant_near_floor']))
        crater = (self.h <= cleared_ceil) & self.mask
        # Out-of-cake neighbours are SUPPORT, never a crater (the loaf perimeter survives).
        def shift(arr, dz, dx):
            out = np.zeros_like(arr)
            zs = slice(max(dz, 0), arr.shape[0] + min(dz, 0))
            zd = slice(max(-dz, 0), arr.shape[0] + min(-dz, 0))
            xs = slice(max(dx, 0), arr.shape[1] + min(dx, 0))
            xd = slice(max(-dx, 0), arr.shape[1] + min(-dx, 0))
            out[zd, xd] = arr[zs, xs]
            return out
        left, right = shift(crater, 0, -1), shift(crater, 0, 1)
        back, front = shift(crater, -1, 0), shift(crater, 1, 0)
        n = left.astype(int) + right.astype(int) + back.astype(int) + front.astype(int)
        collapse = (
            self.mask & (self.h > floor_units) & (n > 0)
            & ((self.h <= near_floor)
               | (n >= SIM['remnant_min_cleared_neighbors'])
               | (left & right) | (back & front))
        )
        swept_units += int((self.h[collapse] - floor_units).sum())
        self.h[collapse] = floor_units
        return swept_units / UNITS_PER_STUD * self.cell * self.cell


# ── the player ───────────────────────────────────────────────────────────────

@dataclass
class Stats:
    upgrades: dict
    tiers: dict = field(default_factory=dict)

    def tier(self, stat):
        return self.tiers.get(stat, 0)

    def value(self, stat):
        return self.upgrades[stat].value(self.tier(stat))

    def next_cost(self, stat):
        up = self.upgrades[stat]
        t = self.tier(stat)
        return up.costs[t] if t < len(up.costs) else None

    def total_cost(self):
        return sum(sum(u.costs) for u in self.upgrades.values())

    def owned_tiers(self):
        return sum(self.tiers.values())

    def max_tiers(self):
        return sum(len(u.costs) for u in self.upgrades.values())


@dataclass
class RunResult:
    minutes: float
    eat_minutes: float
    gym_minutes: float
    bites: int
    food: float
    banked: float
    waste_pct: float
    tiers: int
    max_tiers: int
    progress_at_max: float          # fraction of cake eaten when the tree completed (None -> never)
    minutes_at_max: float
    trips: int
    # One entry per gym trip: (capacity tier OWNED while that belly filled,
    # SECONDS OF EATING it took to fill it, fraction of the cake eaten by then).
    # This is the "how often am I sent to burn fat?" curve — the pacing the player
    # actually feels, and the thing the flat 84000 capacity made invisible.
    fills: list = field(default_factory=list)


def simulate_run(work=1.0, calories_mult=1.0, seed=1, upgrades=None, trip_seconds=14.0,
                 buy=True, fixed_tiers=None, comp=COMP, progress_log=None):
    """One cake, mown band by band, buying tiers from banked calories as it goes."""
    rng = random.Random(seed)
    bands = roll_composition(work, rng, comp)
    fld = Field(bands, comp=comp)
    stats = Stats(upgrades or live_upgrades())
    if fixed_tiers is not None:
        stats.tiers = dict(fixed_tiers)

    total_edible = 0.0
    for b in bands[1:]:
        total_edible += b.thickness * b.density
    total_edible *= float(fld.mask.sum()) * fld.cell * fld.cell

    bites = 0
    food_total = 0.0
    forfeited = 0.0
    banked = 0.0
    eat_seconds = 0.0
    gym_seconds = 0.0
    trips = 0
    belly = 0.0
    stored = 0.0
    progress_at_max = None
    minutes_at_max = None
    fills = []
    eat_seconds_at_last_trip = 0.0

    def try_buy():
        """Greedy cheapest-first: the policy that maximises tier COUNT."""
        nonlocal banked
        bought = 0
        while True:
            best, best_cost = None, None
            for stat in stats.upgrades:
                cost = stats.next_cost(stat)
                if cost is not None and cost <= banked and (best_cost is None or cost < best_cost):
                    best, best_cost = stat, cost
            if best is None:
                return bought
            banked -= best_cost
            stats.tiers[best] = stats.tier(best) + 1
            bought += 1

    def gym_trip(record=True):
        """Belly -> banked calories. Passive drain only == the conservative bound."""
        nonlocal belly, stored, banked, gym_seconds, trips, eat_seconds_at_last_trip
        # Recorded BEFORE the purchase pass, so the tier credited is the one the
        # player owned while that belly was filling.
        # ⚠ `record=False` for the end-of-run flush: that belly was never FULL (the
        # cake ran out first), so counting its short interval would drag the last
        # capacity tier's average down by ~9% and make the published curve look
        # like it sags at the top.
        if record:
            fills.append((stats.tier('capacity'), eat_seconds - eat_seconds_at_last_trip,
                          food_total / total_edible))
        eat_seconds_at_last_trip = eat_seconds
        gym_eff = stats.value('gymEff')
        instant = stats.value('instantBurn')
        burn_speed = stats.value('burnSpeed')
        banked += stored * gym_eff
        stored = 0.0
        belly = 0.0
        trips += 1
        remaining = max(0.0, 1.0 - instant)
        gym_seconds += trip_seconds + (remaining / burn_speed if burn_speed > 0 else 0.0)

    for band_index in range(len(bands) - 1, 0, -1):
        band = bands[band_index]
        floor_units = studs_to_units(band.bottom)
        hardness, cal_per_stud3 = LAYERS[band.layer]
        guard = 0
        while guard < 60000:
            guard += 1
            in_band = fld.mask & (fld.h > floor_units)
            if not in_band.any():
                break
            flat = np.where(in_band, fld.h, -1)
            z, x = np.unravel_index(int(np.argmax(flat)), flat.shape)
            px, pz = cell_to_world(fld.size, fld.cell, GRID['origin_x'], GRID['origin_z'], x, z)

            radius = max(SIM['min_bite_radius'], stats.value('biteRadius') * band.scoop)
            removed = fld.apply_bite(px, pz, radius, stats.value('biteDepth'),
                                     floor_units, SIM['bite_clear_ref_depth'])
            bites += 1
            eat_seconds += 1.0 / stats.value('eatSpeed')

            food = removed * band.density
            food_total += food
            belly += food
            stored += food * cal_per_stud3 * calories_mult

            if belly >= stats.value('capacity'):
                gym_trip()
                if buy:
                    try_buy()
                    if progress_at_max is None and stats.owned_tiers() >= stats.max_tiers():
                        progress_at_max = food_total / total_edible
                        minutes_at_max = (eat_seconds + gym_seconds) / 60.0

            # ScanStats runs at 1 Hz; the eater bites at `eatSpeed`/s.
            if bites % max(1, int(stats.value('eatSpeed'))) == 0:
                forfeited += fld.sweeps(floor_units, band) * band.density
        forfeited += fld.sweeps(floor_units, band) * band.density
        if progress_log is not None:
            progress_log.append((band_index, food_total / total_edible,
                                 (eat_seconds + gym_seconds) / 60.0, stats.owned_tiers()))

    if stored > 0 or belly > 0:
        gym_trip(record=False)
        if buy:
            try_buy()
            if progress_at_max is None and stats.owned_tiers() >= stats.max_tiers():
                progress_at_max = food_total / total_edible
                minutes_at_max = (eat_seconds + gym_seconds) / 60.0

    return RunResult(
        minutes=(eat_seconds + gym_seconds) / 60.0,
        eat_minutes=eat_seconds / 60.0,
        gym_minutes=gym_seconds / 60.0,
        bites=bites,
        food=food_total,
        banked=banked,
        waste_pct=forfeited / max(1.0, food_total + forfeited) * 100.0,
        tiers=stats.owned_tiers(),
        max_tiers=stats.max_tiers(),
        progress_at_max=progress_at_max,
        minutes_at_max=minutes_at_max,
        trips=trips,
        fills=fills,
    )


def maxed_tiers(upgrades):
    return {stat: len(up.costs) for stat, up in upgrades.items()}


# ── reporting ────────────────────────────────────────────────────────────────

def validate(seeds=(1, 2, 3), work=None):
    """Reproduce the endpoint numbers the Luau harness published for this config."""
    print('-' * 100)
    print('VALIDATION — endpoints vs the Luau harness (tools/headless-sim, section B)')
    print('!! the "fresh" row is NOT a session: since ADR-0019 `capacity` base is sized for the')
    print('  first ~10 s of a run, so a tier-0 eater clearing a whole cake is a hypothetical whose')
    print('  gym time is hundreds of trips nobody makes. Both rows still bound the BITE MATH; the')
    print('  number a player lives through is the mid-run report below.')
    print('-' * 100)
    ups = live_upgrades()
    work = MATCH_WORK['easy'] if work is None else work
    for label, tiers in (('fresh (no upgrades)', {}), ('fully upgraded', maxed_tiers(ups))):
        runs = [simulate_run(work=work, seed=s, upgrades=live_upgrades(), buy=False,
                             fixed_tiers=tiers)
                for s in seeds]
        mean = lambda f: sum(f(r) for r in runs) / len(runs)  # noqa: E731
        print('  %-22s %6.1f min  (eat %5.1f + gym %5.1f, %2d trips)  bites %6d  food %10.0f  waste %.1f%%'
              % (label, mean(lambda r: r.minutes), mean(lambda r: r.eat_minutes),
                 mean(lambda r: r.gym_minutes), mean(lambda r: r.trips),
                 mean(lambda r: r.bites), mean(lambda r: r.food), mean(lambda r: r.waste_pct)))


def report(upgrades=None, comp=COMP, seeds=(1, 2, 3), label='live config', work=None):
    ups = upgrades or live_upgrades()
    work = MATCH_WORK['easy'] if work is None else work
    print('-' * 100)
    print('RUN WITH MID-RUN PURCHASES — %s (solo easy, work x%.2f)' % (label, work))
    print('-' * 100)
    total = sum(sum(u.costs) for u in ups.values())
    print('  whole tree costs %s calories across %d tiers'
          % ('{:,}'.format(int(total)), sum(len(u.costs) for u in ups.values())))
    rows = []
    for s in seeds:
        r = simulate_run(work=work, seed=s,
                         upgrades=live_upgrades() if upgrades is None else ups, comp=comp)
        rows.append(r)
        at = ('%.0f%% of the cake (%.0f min)' % (r.progress_at_max * 100, r.minutes_at_max)
              if r.progress_at_max is not None else 'NEVER')
        print('  seed %-6d %6.1f min  tiers %2d/%2d  all-tiers-owned at %-26s  income %s  waste %.1f%%'
              % (s, r.minutes, r.tiers, r.max_tiers, at, '{:,}'.format(int(r.banked + total if r.progress_at_max else r.banked)), r.waste_pct))
    mean_min = sum(r.minutes for r in rows) / len(rows)
    done = [r for r in rows if r.progress_at_max is not None]
    print('  MEAN clear %.1f min | tree completed in %d/%d seeds%s'
          % (mean_min, len(done), len(rows),
             (' at mean %.0f%% of the cake' % (100 * sum(r.progress_at_max for r in done) / len(done)))
             if done else ''))
    return mean_min, (sum(r.progress_at_max for r in done) / len(done)) if done else None


def scaled_upgrades(cost_scale: float, instant_scale: float = 1.0):
    ups = live_upgrades()
    for stat, up in ups.items():
        scale = cost_scale * (instant_scale if stat == 'instantBurn' else 1.0)
        up.costs = [int(round(c * scale / 100.0) * 100) for c in up.costs]
    return ups


# ⚠ `candidate_upgrades()` / `check_candidate()` / the `--candidate` flag were
# REMOVED on 2026-08-05. They pinned the 2026-07-30 proposal's cost table while
# reading every other value from `live_upgrades()`, so after ADR-0019 the flag
# measured a config that has never existed — the new capacity/burnSpeed VALUES
# against the retired COSTS — and printed it as "the candidate", i.e. as a proposal
# to revert this rebalance, complete with a stale "was 16,019,500" baseline.
# A frozen proposal in a live model is a trap: freeze BOTH halves or neither.
# To evaluate a new table, pass it to `report(upgrades=...)` / `intervals(upgrades=...)`.


def intervals(upgrades=None, seeds=(1, 2, 3, 4, 5), work=None, label='live config'):
    """How OFTEN is the player sent to burn fat, and does that change as they upgrade?

    The design target (user request, 2026-08-05; ADR-0019) is a VISIBLE stretch:
    ~10 s per belly at tier 0, ~30 s at capacity tier 1, ~90 s at tier 2, then
    120/150/180. Before that request the curve ran BACKWARDS (227 s at tier 0 down
    to 102 s at tier 5) because capacity grew 4x while eating power grows ~20x.

    TWO different statistics, and the docs cite the FIRST one:

      `first s`  the belly the player fills IMMEDIATELY AFTER buying that capacity
                 tier. This is the number ADR-0019 and features/upgrades.md quote,
                 because it is what the purchase FEELS like at the moment of
                 purchase, and it is what the tuning was solved against.
      `mean s`   the average over every belly filled while owning that tier. It is
                 systematically LOWER, and legitimately so: the player keeps buying
                 EATING tiers inside the bucket, so each successive belly at a fixed
                 capacity fills faster than the last. A bucket whose mean is well
                 under its first is a bucket the player spent a long time in.

    `n` is how many bellies land in the bucket, i.e. how many gym trips — and
    therefore how many purchase moments — that tier is responsible for. The
    end-of-run PARTIAL belly is excluded (see `gym_trip(record=False)`).
    """
    ups = upgrades or live_upgrades()
    work = MATCH_WORK['easy'] if work is None else work
    print('-' * 100)
    print('BELLY-FILL INTERVAL by capacity tier - %s (solo easy, work x%.2f, %d seeds)'
          % (label, work, len(seeds)))
    print('  `first s` = the belly right after buying that tier (the number the docs quote);')
    print('  `mean s`  = averaged over the whole bucket, and lower by construction - eating')
    print('              tiers keep arriving while the capacity tier stays put.')
    print('-' * 100)
    buckets, firsts = {}, {}
    trips_total = 0
    for s in seeds:
        r = simulate_run(work=work, seed=s,
                         upgrades=live_upgrades() if upgrades is None else ups)
        trips_total += r.trips
        seen = set()
        for tier, seconds, progress in r.fills:
            buckets.setdefault(tier, []).append((seconds, progress))
            if tier not in seen:
                firsts.setdefault(tier, []).append(seconds)
                seen.add(tier)
    print('  %-14s %9s %6s %9s %9s %9s %13s'
          % ('capacity tier', 'value', 'n', 'first s', 'mean s', 'median s', 'cake eaten'))
    for tier in sorted(buckets):
        rows = buckets[tier]
        secs = sorted(x[0] for x in rows)
        first = firsts.get(tier) or []
        span = '%.0f%%-%.0f%%' % (100 * min(x[1] for x in rows), 100 * max(x[1] for x in rows))
        print('  tier %-9d %9s %6d %8.1fs %8.1fs %8.1fs %13s'
              % (tier, '{:,}'.format(int(ups['capacity'].value(tier))), len(secs),
                 (sum(first) / len(first)) if first else float('nan'),
                 sum(secs) / len(secs), secs[len(secs) // 2], span))
    print('  %d gym trips over %d seeds (%.1f per cake)'
          % (trips_total, len(seeds), trips_total / len(seeds)))
    return buckets, firsts


def solve(seeds=(1, 2, 3)):
    """Find a cost scale that completes the tree by ~50% of the cake, then a work
    multiplier that puts the clear time back at ~40 min."""
    print('=' * 100)
    print('SOLVE — target: whole tree owned by 50% of the cake, ~40 min solo clear')
    print('=' * 100)
    for cost_scale in (1.0, 0.5, 0.3, 0.2, 0.15, 0.12, 0.1, 0.08, 0.06):
        for instant_scale in (1.0, 0.35):
            ups = scaled_upgrades(cost_scale, instant_scale)
            rows = [simulate_run(seed=s, upgrades=scaled_upgrades(cost_scale, instant_scale))
                    for s in seeds]
            done = [r for r in rows if r.progress_at_max is not None]
            mean_min = sum(r.minutes for r in rows) / len(rows)
            at = (100 * sum(r.progress_at_max for r in done) / len(done)) if done else float('nan')
            print('  costs x%-5.2f instantBurn x%-4.2f -> clear %5.1f min | tree done in %d/%d seeds at %5.1f%% | total cost %12s'
                  % (cost_scale, instant_scale, mean_min, len(done), len(rows), at,
                     '{:,}'.format(int(sum(sum(u.costs) for u in ups.values())))))


def grid_search(seeds=(1, 2, 3)):
    """Finer sweep: cost scale x work multiplier, reporting BOTH targets.

    They are coupled — cheaper tiers finish the tree sooner, which makes the
    player stronger sooner, which shortens the clear. More `work` lengthens the
    clear AND raises total income, so it pushes completion to an earlier % of the
    cake. So the two targets do not fight each other.
    """
    print('=' * 100)
    print('GRID — targets: clear ~40 min, whole tree owned by <=50% of the cake')
    print('=' * 100)
    print('  %-9s %-6s %8s %10s %8s %14s' % ('costs', 'work', 'clear', 'tree@', 'seeds', 'total cost'))
    for cost_scale in (0.05, 0.06, 0.07, 0.08):
        for work in (1.0, 1.08, 1.16, 1.25):
            rows = [simulate_run(work=work, seed=s,
                                 upgrades=scaled_upgrades(cost_scale, 0.35))
                    for s in seeds]
            done = [r for r in rows if r.progress_at_max is not None]
            mean_min = sum(r.minutes for r in rows) / len(rows)
            at = (100 * sum(r.progress_at_max for r in done) / len(done)) if done else float('nan')
            flag = ''
            if 38 <= mean_min <= 42 and done and len(done) == len(rows) and at <= 50:
                flag = '   <== HITS BOTH'
            print('  x%-8.2f %-6.2f %6.1f m %9.1f%% %6d/%d %14s%s'
                  % (cost_scale, work, mean_min, at, len(done), len(rows),
                     '{:,}'.format(int(sum(sum(u.costs) for u in scaled_upgrades(cost_scale, 0.35).values()))),
                     flag))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--solve', action='store_true')
    parser.add_argument('--grid', action='store_true')
    parser.add_argument('--intervals', action='store_true',
                        help='belly-fill seconds bucketed by capacity tier (the "how often '
                             'am I sent to the gym?" curve)')
    parser.add_argument('--work', type=float, default=1.0)
    args = parser.parse_args()

    problems = check_config_sync()
    if problems:
        print('!! MODEL OUT OF SYNC WITH THE LUA CONFIG — fix before trusting any number below')
        for p in problems:
            print('   ' + p)
        print()
    else:
        print('config sync: OK (every mirrored constant matches the Lua source)\n')

    if args.grid:
        grid_search()
        return 1 if problems else 0
    if args.intervals:
        # `--work 1` is argparse's default, so only an EXPLICIT value overrides easy.
        intervals(work=args.work if args.work != 1.0 else None)
        return 1 if problems else 0

    validate()
    print()
    report()
    if args.solve:
        print()
        solve()
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
