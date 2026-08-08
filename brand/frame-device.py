#!/usr/bin/env python3
"""Composite a raw iOS screenshot into an iPhone-style device frame.

README screenshots read better inside a handset: it tells the reader at a
glance that this is a phone app, and stops the flat white login screen from
dissolving into GitHub's white page background.

Everything is derived from the screenshot width so the geometry holds at any
resolution. Output is RGBA with a transparent margin, so the frame sits on
both the light and dark GitHub themes.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter


def frame(src, dst):
    shot = Image.open(src).convert("RGB")
    w, h = shot.size

    bezel = round(w * 0.030)      # black border around the glass
    rail = round(w * 0.010)       # bright edge suggesting the titanium band
    pad = round(w * 0.055)        # transparent margin for the shadow + buttons
    screen_r = round(w * 0.098)   # screen corner radius
    body_r = screen_r + bezel

    bw, bh = w + bezel * 2, h + bezel * 2
    cw, ch = bw + pad * 2, bh + pad * 2
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    # Drop shadow first, so the body sits on top of it.
    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + round(h * 0.004), pad + bw, pad + bh + round(h * 0.004)],
        body_r, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(round(w * 0.018))))

    d = ImageDraw.Draw(canvas)
    # Outer band, then the black body inset within it.
    d.rounded_rectangle([pad - rail, pad - rail, pad + bw + rail, pad + bh + rail],
                        body_r + rail, fill=(209, 211, 215, 255))
    d.rounded_rectangle([pad, pad, pad + bw, pad + bh], body_r, fill=(24, 24, 26, 255))

    # Side buttons: volume pair and action button left, power right.
    btn = (176, 178, 183, 255)
    bx_l, bx_r = pad - rail, pad + bw + rail
    for top, length in ((0.150, 0.052), (0.232, 0.086), (0.335, 0.086)):
        y = pad + round(bh * top)
        d.rounded_rectangle([bx_l - round(w * 0.008), y, bx_l + 1, y + round(bh * length)],
                            round(w * 0.004), fill=btn)
    y = pad + round(bh * 0.245)
    d.rounded_rectangle([bx_r - 1, y, bx_r + round(w * 0.008), y + round(bh * 0.130)],
                        round(w * 0.004), fill=btn)

    # Round the screenshot's own corners so it matches the glass.
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w, h], screen_r, fill=255)
    canvas.paste(shot, (pad + bezel, pad + bezel), mask)

    canvas.save(dst)
    return canvas.size


if __name__ == "__main__":
    size = frame(sys.argv[1], sys.argv[2])
    print(f"  {os.path.basename(sys.argv[2])}  {size[0]}x{size[1]}")
