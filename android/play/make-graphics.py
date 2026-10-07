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
    bottom = int(centred(d, caption, 90, font(66), WHITE, w)) + 30
    shot = Image.open(os.path.join(BRAND, "framed", framed)).convert("RGBA")
    # The whole handset fits under the caption: the bottom of the screen (the
    # composer, the Accept and Decline buttons) is often the point of the shot.
    sh = h - bottom - 50
    sw = round(shot.width * sh / shot.height)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    im.paste(shot, ((w - sw) // 2, bottom), shot)
    im.save(os.path.join(OUT, name))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    icon()
    feature()
    # Raw emulator captures are in brand/screenshots/play/ (staged on the local QA
    # server, demo-mode status bar); brand/frame-device.py turns them into these.
    shots = [
        ("play-02-group.png", "Group chats that stay\nin the family"),
        ("play-01-chats.png", "No ads, no feed,\njust your people"),
        ("play-03-request.png", "New people have to\nask first"),
        ("play-06-dark.png", "Message or call,\nday or night"),
        ("play-04-stickers.png", "Stickers and emoji,\none tap away"),
        ("play-05-qr.png", "Add each other\nwith a QR code"),
    ]
    for old in os.listdir(OUT):
        if old.startswith("phone-"):
            os.remove(os.path.join(OUT, old))
    for i, (framed, caption) in enumerate(shots, 1):
        phone(f"phone-{i}-{framed[8:-4]}.png", framed, caption)
    for f in sorted(os.listdir(OUT)):
        print(f, Image.open(os.path.join(OUT, f)).size)
