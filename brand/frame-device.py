#!/usr/bin/env python3
"""Composite a raw phone screenshot into a device frame.

    frame-device.py <screenshot> <output> [ios|android]

README screenshots read better inside a handset: it tells the reader at a
glance that this is a phone app, and stops the mostly-white screens from
dissolving into GitHub's white page background.

Two styles, because putting an iPhone bezel around an Android screenshot would
misrepresent what the reader is looking at. They differ where the real devices
do: corner radius, which edges carry buttons, and whether there is a punch-hole
camera in the status bar.

All geometry is derived from the screenshot width, so the same script works at
any resolution. Output is RGBA with a transparent margin so the frame sits on
both the light and dark GitHub themes.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

STYLES = {
    # radius, bezel, band colour, button colour, punch-hole
    "ios": dict(screen_r=0.098, bezel=0.030, band=(209, 211, 215), btn=(176, 178, 183),
                punch=False),
    # Pixel-style: slightly squarer glass, a marginally thicker bezel, a warmer
    # aluminium band, and a centred front camera.
    "android": dict(screen_r=0.072, bezel=0.034, band=(196, 198, 202), btn=(150, 152, 157),
                    punch=True),
}


def frame(src, dst, style="ios"):
    cfg = STYLES[style]
    shot = Image.open(src).convert("RGB")
    w, h = shot.size

    bezel = round(w * cfg["bezel"])
    rail = round(w * 0.010)
    pad = round(w * 0.055)
    screen_r = round(w * cfg["screen_r"])
    body_r = screen_r + bezel

    bw, bh = w + bezel * 2, h + bezel * 2
    cw, ch = bw + pad * 2, bh + pad * 2
    canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + round(h * 0.004), pad + bw, pad + bh + round(h * 0.004)],
        body_r, fill=(0, 0, 0, 90))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(round(w * 0.018))))

    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([pad - rail, pad - rail, pad + bw + rail, pad + bh + rail],
                        body_r + rail, fill=cfg["band"] + (255,))
    d.rounded_rectangle([pad, pad, pad + bw, pad + bh], body_r, fill=(24, 24, 26, 255))

    btn = cfg["btn"] + (255,)
    bx_l, bx_r = pad - rail, pad + bw + rail
    thick, r = round(w * 0.008), round(w * 0.004)
    if style == "ios":
        # Action button and volume pair left, power right.
        for top, length in ((0.150, 0.052), (0.232, 0.086), (0.335, 0.086)):
            y = pad + round(bh * top)
            d.rounded_rectangle([bx_l - thick, y, bx_l + 1, y + round(bh * length)], r, fill=btn)
        y = pad + round(bh * 0.245)
        d.rounded_rectangle([bx_r - 1, y, bx_r + thick, y + round(bh * 0.130)], r, fill=btn)
    else:
        # Android convention: power above the volume rocker, both on the right.
        for top, length in ((0.170, 0.062), (0.255, 0.105)):
            y = pad + round(bh * top)
            d.rounded_rectangle([bx_r - 1, y, bx_r + thick, y + round(bh * length)], r, fill=btn)

    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, w, h], screen_r, fill=255)
    canvas.paste(shot, (pad + bezel, pad + bezel), mask)

    if cfg["punch"]:
        # Centred front camera. It lands in the empty gap between the clock and
        # the status icons, so it never covers anything the screenshot is showing.
        cr = round(w * 0.017)
        cx = pad + bezel + w // 2
        cy = pad + bezel + round(h * 0.0175)
        d.ellipse([cx - cr, cy - cr, cx + cr, cy + cr], fill=(12, 12, 14, 255))
        d.ellipse([cx - cr + 2, cy - cr + 2, cx + cr - 2, cy + cr - 2], fill=(30, 34, 46, 255))

    canvas.save(dst)
    return canvas.size


if __name__ == "__main__":
    style = sys.argv[3] if len(sys.argv) > 3 else "ios"
    size = frame(sys.argv[1], sys.argv[2], style)
    print(f"  {os.path.basename(sys.argv[2])}  {size[0]}x{size[1]}  ({style})")
