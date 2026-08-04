#!/usr/bin/env python3
"""Generate BLML chat wallpapers: the built-in default tiles and the server
gallery. All tiles are seamless, deliberately sparse — a handful of small
line motifs with lots of clear space — after the first, denser set proved
distracting behind message bubbles.

Outputs:
  brand/chat-wallpaper-{light,dark}.png       default app tiles
  webapp/img/bkg/d1*.png, l1*.png             gallery: 6 dark + 6 light

Run from anywhere; paths resolve relative to this file. Deterministic: same
seeds -> same pixels, so regeneration does not churn git.
"""
import math
import os
import random
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
TILE = 512

# Palette. Dark backgrounds sit below the app's dark chat colour (#0b141a) so
# the wallpaper reads as canvas, not content; strokes stay a few steps above
# the background — visible, never loud.
DARK_BG, DARK_LINE = (7, 13, 17), (38, 50, 58)
LIGHT_BG, LIGHT_LINE = (244, 240, 234), (211, 202, 192)
# Default tiles are quieter still: they are behind every chat by default.
DEF_DARK_BG, DEF_DARK_LINE = (8, 15, 19), (28, 39, 46)
DEF_LIGHT_BG, DEF_LIGHT_LINE = (236, 229, 221), (214, 205, 195)


def wrap_draw(draw_fn, xy, size):
    """Draw a motif at xy and at the 8 wrapped positions so tiles stay
    seamless when the motif overlaps an edge."""
    x, y = xy
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw_fn((x + dx, y + dy))


def motif_ring(d, c, r, line, w):
    x, y = c
    d.ellipse([x - r, y - r, x + r, y + r], outline=line, width=w)


def motif_dot(d, c, r, line, _w):
    # Filled shapes carry far more visual weight than line work at the same
    # radius, so dots render at under half the nominal size.
    x, y = c
    r = max(2.5, r * 0.4)
    d.ellipse([x - r, y - r, x + r, y + r], fill=line)


def motif_plus(d, c, r, line, w):
    x, y = c
    d.line([x - r, y, x + r, y], fill=line, width=w)
    d.line([x, y - r, x, y + r], fill=line, width=w)


def motif_sparkle(d, c, r, line, w):
    x, y = c
    d.line([x - r, y, x + r, y], fill=line, width=w)
    d.line([x, y - r, x, y + r], fill=line, width=w)
    s = r * 0.45
    d.line([x - s, y - s, x + s, y + s], fill=line, width=max(1, w - 1))
    d.line([x - s, y + s, x + s, y - s], fill=line, width=max(1, w - 1))


def motif_wave(d, c, r, line, w):
    x, y = c
    pts = []
    for i in range(13):
        t = i / 12
        pts.append((x - r + 2 * r * t, y + math.sin(t * math.pi * 2) * r * 0.28))
    d.line(pts, fill=line, width=w)


def motif_arc(d, c, r, line, w):
    x, y = c
    d.arc([x - r, y - r, x + r, y + r], start=200, end=340, fill=line, width=w)


MOTIFS = {
    'sparkle': motif_sparkle,
    'ring': motif_ring,
    'dot': motif_dot,
    'plus': motif_plus,
    'wave': motif_wave,
    'arc': motif_arc,
}


def make_tile(kinds, count, bg, line, seed, size=TILE, rmin=8, rmax=18, width=2):
    """A sparse seamless tile: `count` motifs scattered with a minimum gap so
    they never clump into the visual noise this generator exists to avoid."""
    rng = random.Random(seed)
    im = Image.new('RGB', (size, size), bg)
    d = ImageDraw.Draw(im)
    placed = []
    attempts = 0
    while len(placed) < count and attempts < count * 60:
        attempts += 1
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        # Toroidal min-distance keeps spacing honest across tile edges too.
        ok = True
        for px, py in placed:
            ddx = min(abs(x - px), size - abs(x - px))
            ddy = min(abs(y - py), size - abs(y - py))
            if (ddx * ddx + ddy * ddy) ** 0.5 < size / math.sqrt(count) * 0.75:
                ok = False
                break
        if not ok:
            continue
        placed.append((x, y))
        kind = rng.choice(kinds)
        r = rng.uniform(rmin, rmax)
        wrap_draw(lambda c, k=kind, rr=r: MOTIFS[k](d, c, rr, line, width), (x, y), size)
    return im


def save(im, *path):
    out = os.path.join(ROOT, *path)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    im.save(out, optimize=True)
    print('wrote', os.path.relpath(out, ROOT))


# ── Default app tiles: mixed motifs, very sparse, very low contrast ──────────
save(make_tile(['ring', 'plus', 'wave', 'dot'], 10, DEF_LIGHT_BG, DEF_LIGHT_LINE, seed=11),
     'chat-wallpaper-light.png')
save(make_tile(['ring', 'plus', 'wave', 'dot'], 10, DEF_DARK_BG, DEF_DARK_LINE, seed=11),
     'chat-wallpaper-dark.png')

# ── Gallery: one motif family per design, 6 dark + 6 light ───────────────────
DESIGNS = [
    ('0', ['sparkle'], 9),
    ('1', ['ring'], 8),
    ('2', ['dot'], 14),
    ('3', ['plus'], 10),
    ('4', ['wave'], 8),
    ('5', ['ring', 'dot'], 11),
]
for suffix, kinds, count in DESIGNS:
    seed = 100 + int(suffix)
    save(make_tile(kinds, count, DARK_BG, DARK_LINE, seed=seed),
         '..', 'webapp', 'img', 'bkg', 'd1%s.png' % suffix)
    save(make_tile(kinds, count, LIGHT_BG, LIGHT_LINE, seed=seed),
         '..', 'webapp', 'img', 'bkg', 'l1%s.png' % suffix)
