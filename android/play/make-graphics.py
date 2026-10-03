#!/usr/bin/env python3
"""Build the Google Play store graphics from the brand assets.

    python3 android/play/make-graphics.py

Writes into android/play/graphics/:
  icon-512.png             512x512 app icon (Play applies its own corner mask)
  feature-graphic.png      1024x500 banner shown at the top of the listing
  phone-N-*.png            1080x1920 phone screenshots

Play rejects phone screenshots whose long side is more than twice the short
side, and the emulator's own 1080x2400 captures are, so each screenshot is the
framed capture from brand/framed/ set on a 9:16 canvas under a caption.
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
BRAND = os.path.join(HERE, "..", "..", "brand")
OUT = os.path.join(HERE, "graphics")
NAVY = (14, 27, 82)          # launcherBackground in colors.xml
WHITE = (255, 255, 255)
SOFT = (196, 205, 240)
FONTS = "/System/Library/Fonts/Avenir Next.ttc"


def font(size, weight="Bold"):
    # The collection holds every weight; pick the face by its style name.
    for index in range(12):
        try:
            f = ImageFont.truetype(FONTS, size, index=index)
        except OSError:
            break
        if f.getname()[1] == weight:
            return f
    return ImageFont.truetype(FONTS, size)


def centred(draw, text, y, f, fill, width):
    for line in text.split("\n"):
        w = draw.textlength(line, font=f)
        draw.text(((width - w) / 2, y), line, font=f, fill=fill)
        y += f.size * 1.22
    return y


def icon():
    Image.open(os.path.join(BRAND, "icon.png")).convert("RGB") \
        .resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, "icon-512.png"))


def feature():
    im = Image.new("RGB", (1024, 500), NAVY)
    logo = Image.open(os.path.join(BRAND, "logo-transparent.png")).convert("RGBA")
    logo = logo.resize((420, 420), Image.LANCZOS)
    im.paste(logo, (44, 40), logo)
    d = ImageDraw.Draw(im)
    d.text((500, 150), "Private chat for", font=font(50), fill=WHITE)
    d.text((500, 212), "family and friends", font=font(50), fill=WHITE)
    d.text((500, 300), "No ads. No algorithms.", font=font(30, "Medium"), fill=SOFT)
    d.text((500, 342), "On a server you control.", font=font(30, "Medium"), fill=SOFT)
    im.save(os.path.join(OUT, "feature-graphic.png"))


def phone(name, framed, caption):
    w, h = 1080, 1920
    im = Image.new("RGB", (w, h), NAVY)
    d = ImageDraw.Draw(im)
    bottom = centred(d, caption, 110, font(68), WHITE, w)
    shot = Image.open(os.path.join(BRAND, "framed", framed)).convert("RGBA")
    # The handset runs off the bottom edge, so the screen is as large as it can be.
    sw = 860
    shot = shot.resize((sw, round(shot.height * sw / shot.width)), Image.LANCZOS)
    im.paste(shot, ((w - sw) // 2, int(bottom) + 60), shot)
    im.save(os.path.join(OUT, name))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon()
    feature()
    phone("phone-1-conversation.png", "android-conversation.png", "Group chats that stay\nin the family")
    phone("phone-2-chats.png", "android-chats.png", "No ads, no feed,\njust your people")
    for f in sorted(os.listdir(OUT)):
        print(f, Image.open(os.path.join(OUT, f)).size)
