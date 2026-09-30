"""Rebuild the README images from renders of the real app screens.

Run from anywhere:  python docs/readme/build_images.py
Needs Pillow. Reads app/test/readme/out/*.png and writes hero, scores and
coach PNGs next to this script.

The renders come from a local render harness that is not part of the public
repo (app/test/readme/readme_screens_test.dart). It draws each screen at
412x915 logical px, dark, with the demo dataset shown as connected data on
one fixed day, so every screen reads the same Recovery. To refresh them:

    cd app && flutter test test/readme/readme_screens_test.dart --update-goldens

Screens are scaled to 412 px wide (never cropped sideways) and cropped from
the top to one 915 px viewport, or less where a screen would end mid-line.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
APP = os.path.join(ROOT, "app")
SCREENS = os.path.join(APP, "test", "readme", "out")
OUT = os.path.dirname(os.path.abspath(__file__))

BG = (8, 8, 8)
EDGE = (38, 38, 40)
LABEL = (150, 150, 155)
FONT_PATH = os.path.join(APP, "assets", "fonts", "DMSans", "DMSans-Variable.ttf")

PHONE_W, PHONE_H = 412, 915
GAP, PAD = 40, 56
RADIUS = 34

# Every render this script uses.
NEEDED = [
    "today.png", "recovery_ring.png", "sleep.png", "trends.png",
    "strain.png", "journal.png", "live.png",
    "coach_empty.png", "coach_answer.png",
]

# Screens that scroll on past the phone end in a gap between cards, never
# mid-line.
CUT = 900


def check_renders():
    """Stop with a clear message when the renders are not on this machine."""
    rel = os.path.relpath(SCREENS, ROOT)
    if not os.path.isdir(SCREENS):
        sys.exit(
            f"No screen renders found in {rel}/.\n"
            "They come from a local render harness that is not in the public repo,\n"
            "so a fresh clone cannot rebuild these images. The PNGs committed in\n"
            "docs/readme/ are the current ones. With the harness in place, run:\n"
            "  cd app && flutter test test/readme/readme_screens_test.dart --update-goldens"
        )
    missing = [n for n in NEEDED if not os.path.isfile(os.path.join(SCREENS, n))]
    if missing:
        sys.exit(f"Missing renders in {rel}/: {', '.join(missing)}.\n"
                 "Re-run the render harness (see the top of this file).")


def font(size, weight=500):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_axes([14, weight])  # opsz, wght
    except Exception:
        pass
    return f


def load_phone(name, crop_h=PHONE_H):
    """Load a render, normalise to 412 px wide, crop to one viewport."""
    im = Image.open(os.path.join(SCREENS, name)).convert("RGB")
    if im.width != PHONE_W:
        h = round(im.height * PHONE_W / im.width)
        im = im.resize((PHONE_W, h), Image.LANCZOS)
    return im.crop((0, 0, PHONE_W, min(crop_h, im.height)))


def rounded(im, radius, border=EDGE):
    """Round the corners (mask drawn at 4x for smooth edges) and add a 1 px edge."""
    s = 4
    w, h = im.size
    mask = Image.new("L", (w * s, h * s), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius * s, fill=255)
    mask = mask.resize((w, h), Image.LANCZOS)
    card = Image.new("RGB", (w, h), BG)
    card.paste(im, (0, 0), mask)
    if border:
        ring = Image.new("L", (w * s, h * s), 0)
        dr = ImageDraw.Draw(ring)
        dr.rounded_rectangle((0, 0, w * s - 1, h * s - 1), radius * s, outline=255, width=s * 2)
        ring = ring.resize((w, h), Image.LANCZOS)
        card.paste(Image.new("RGB", (w, h), border), (0, 0), ring)
    return card


def row(images, labels=None, gap=GAP, pad=PAD, radius=RADIUS):
    label_h = 44 if labels else 0
    tallest = max(i.height for i in images)
    w = sum(i.width for i in images) + gap * (len(images) - 1) + pad * 2
    h = tallest + pad * 2 + label_h
    canvas = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(canvas)
    f = font(22)
    x = pad
    for i, im in enumerate(images):
        canvas.paste(rounded(im, radius), (x, pad))
        if labels:
            t = labels[i]
            tw = d.textlength(t, font=f)
            # One baseline for the row, under the tallest phone.
            d.text((x + (im.width - tw) / 2, pad + tallest + 14), t, font=f, fill=LABEL)
        x += im.width + gap
    return canvas


def save(im, name):
    path = os.path.join(OUT, name)
    im.save(path, optimize=True)
    print(name, im.size, os.path.getsize(path) // 1024, "KB")


check_renders()

# 1. Hero: one morning (Sat 26 Sep, Recovery 57) on four screens: Today,
#    Recovery scrolled to its ring and breakdown, Sleep, Trends.
save(row([load_phone("today.png"), load_phone("recovery_ring.png", CUT),
          load_phone("sleep.png"), load_phone("trends.png")]),
     "hero.png")

# 2. Scores and training, the same day: Strain, Journal, Live workout.
save(row([load_phone("strain.png"), load_phone("journal.png", CUT),
          load_phone("live.png")],
         labels=["Strain against today's goal", "Journal: links, not causes",
                 "Live heart rate over Bluetooth"]),
     "scores.png")

# 3. Coach: the empty chat and the answer to "Why is my Recovery lower today?".
save(row([load_phone("coach_empty.png"), load_phone("coach_answer.png")],
         labels=["Works on the phone, no setup", "Answers from your own numbers"]),
     "coach.png")
