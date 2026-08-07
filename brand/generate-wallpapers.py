#!/usr/bin/env python3
"""Generate BLML chat wallpapers: the built-in default tiles and the server
gallery. All tiles are seamless, deliberately sparse — a handful of small
line motifs with lots of clear space — after the first, denser set proved
distracting behind message bubbles.

Outputs:
  brand/chat-wallpaper-{light,dark}.png       default app tiles
  webapp/img/bkg/d1*.png, l1*.png             gallery: 7 dark + 7 light
                                              (d16/l16 carry the BLML wordmark)

Run from anywhere; paths resolve relative to this file. Deterministic: same
seeds -> same pixels, so regeneration does not churn git.
"""
import math
import os
import random
from PIL import Image, ImageDraw, ImageFont

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


# ── Branded tile ────────────────────────────────────────────────────────────
# A geometric sans keeps the wordmark reading as texture rather than as a
# logo stamped on the chat. The first font that exists wins; PIL's bitmap
# default is a legible last resort, so generation never hard-fails on a host
# without these installed.
WORDMARK_FONTS = [
    ('/System/Library/Fonts/Avenir Next.ttc', 2),
    ('/System/Library/Fonts/Supplemental/Futura.ttc', 0),
    ('/System/Library/Fonts/HelveticaNeue.ttc', 0),
    ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf', 0),
]


def wordmark_font(px):
    for path, index in WORDMARK_FONTS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px, index=index)
            except Exception:
                continue
    return ImageFont.load_default()


def wordmark_sprite(text, font, line, tracking):
    """Render `text` letter by letter so we can letter-space it. Wide tracking
    is what stops a repeated four-letter word from reading as a logo."""
    glyphs = []
    for ch in text:
        box = font.getbbox(ch)
        glyphs.append((ch, box))
    width = sum(b[2] - b[0] for _, b in glyphs) + tracking * (len(glyphs) - 1)
    top = min(b[1] for _, b in glyphs)
    height = max(b[3] for _, b in glyphs) - top
    sprite = Image.new('RGBA', (max(1, int(width)) + 4, max(1, int(height)) + 4), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sprite)
    x = 2
    for ch, box in glyphs:
        sd.text((x - box[0], 2 - top), ch, font=font, fill=line + (255,))
        x += (box[2] - box[0]) + tracking
    return sprite


def make_wordmark_tile(bg, line, seed, size=TILE, rows=3, px=27, tracking=6):
    """The gallery's branded tile.

    Placement is by even vertical rhythm rather than the scatter the other
    tiles use. The tile is 384px on screen against a ~430px-wide phone, so a
    wordmark repeats roughly once per row: scattering puts two of them in the
    same band often enough to read as a paragraph of repeated text. Fixed rows
    with jittered x keep the spacing calm and deliberate.

    The wordmark is also mixed halfway back toward the background — quieter
    than the dots around it, so the brand is legible without competing with
    the messages sitting on top of it."""
    rng = random.Random(seed)
    im = Image.new('RGB', (size, size), bg)
    d = ImageDraw.Draw(im)
    soft = tuple(round(b + (l - b) * 0.72) for b, l in zip(bg, line))
    sprite = wordmark_sprite('BLML', wordmark_font(px), soft, tracking)
    sw, sh = sprite.size

    marks = []
    for i in range(rows):
        y = (i + 0.5) / rows * size + rng.uniform(-size * 0.045, size * 0.045)
        x = rng.uniform(0, size)
        marks.append((x, y))
        for dx in (-size, 0, size):
            for dy in (-size, 0, size):
                im.paste(sprite, (int(x - sw / 2) + dx, int(y - sh / 2) + dy), sprite)

    # Dots fill the gaps without introducing a second shape language. Keep them
    # clear of the wordmarks so nothing collides with a letter.
    dots, attempts = 0, 0
    while dots < 6 and attempts < 600:
        attempts += 1
        x, y = rng.uniform(0, size), rng.uniform(0, size)
        ok = True
        for mx, my in marks:
            ddx = min(abs(x - mx), size - abs(x - mx))
            ddy = min(abs(y - my), size - abs(y - my))
            if ddx < sw * 0.75 and ddy < sh * 2.2:
                ok = False
                break
        if not ok:
            continue
        marks.append((x, y))
        dots += 1
        wrap_draw(lambda c: motif_dot(d, c, 9, line, 2), (x, y), size)
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

# ── Branded pair, one dark one light ────────────────────────────────────────
save(make_wordmark_tile(DARK_BG, DARK_LINE, seed=206),
     '..', 'webapp', 'img', 'bkg', 'd16.png')
save(make_wordmark_tile(LIGHT_BG, LIGHT_LINE, seed=206),
     '..', 'webapp', 'img', 'bkg', 'l16.png')
