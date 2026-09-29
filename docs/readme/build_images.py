"""Rebuild the README images from the app's golden renders.

Run from anywhere:  python docs/readme/build_images.py
Needs Pillow. Reads app/test/goldens/screens/*.png and writes hero, scores,
coach and sources PNGs next to this script.
Screens are scaled to 412 px wide (never cropped sideways) and cropped to one
915 px viewport from the top. After a UI copy change, regenerate the goldens,
then run this script.
"""
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
APP = os.path.join(ROOT, "app")
SCREENS = os.path.join(APP, "test", "goldens", "screens")
OUT = os.path.dirname(os.path.abspath(__file__))

BG = (8, 8, 8)
EDGE = (38, 38, 40)
LABEL = (150, 150, 155)
FONT_PATH = os.path.join(APP, "assets", "fonts", "DMSans", "DMSans-Variable.ttf")

PHONE_W, PHONE_H = 412, 915
GAP, PAD = 40, 56
RADIUS = 34


def font(size, weight=500):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_axes([14, weight])  # opsz, wght
    except Exception:
        pass
    return f


def load_phone(name, crop_h=PHONE_H):
    """Load a golden screen, normalise to 412 px wide, crop to one viewport."""
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
    w = sum(i.width for i in images) + gap * (len(images) - 1) + pad * 2
    h = max(i.height for i in images) + pad * 2 + label_h
    canvas = Image.new("RGB", (w, h), BG)
    d = ImageDraw.Draw(canvas)
    f = font(22)
    x = pad
    for i, im in enumerate(images):
        canvas.paste(rounded(im, radius), (x, pad))
        if labels:
            t = labels[i]
            tw = d.textlength(t, font=f)
            d.text((x + (im.width - tw) / 2, pad + im.height + 14), t, font=f, fill=LABEL)
        x += im.width + gap
    return canvas


def save(im, name):
    path = os.path.join(OUT, name)
    im.save(path, optimize=True)
    print(name, im.size, os.path.getsize(path) // 1024, "KB")


# 1. Hero: four screens that show the same sample day (Mon 28 Sep, Recovery 78).
save(row([load_phone(n) for n in
          ["today_dark.png", "recovery_dark.png", "sleep_dark.png", "trends_dark.png"]]),
     "hero.png")

# 2. Scores and training: Strain, Journal, Live workout.
save(row([load_phone(n) for n in
          ["strain_dark.png", "journal_dark.png", "live_recording_dark.png"]],
         labels=["Strain vs today's target", "Journal: associations, not causes",
                 "Live heart rate over Bluetooth"]),
     "scores.png")

# 3. Coach: who answers, a verified answer, the facts-only fallback, the red-flag router.
save(row([load_phone(n) for n in
          ["coach_setup_cloud_dark.png", "coach_answer_dark.png",
           "coach_fallback_dark.png", "coach_safety_dark.png"]],
         labels=["On-device by default, BYO key", "Every number cited and checked",
                 "Can't be checked, so facts only", "Red flags never reach a model"]),
     "coach.png")

# 4. Data sources: what it is and isn't, how to start, one source per metric.
# Cropped to 676 px so the strip ends above the Enhanced-mode sign-in notice.
save(row([load_phone(n, crop_h=676) for n in
          ["onboarding_what_dark.png", "onboarding_choose_dark.png", "sources_connected_dark.png"]],
         labels=["What it is, and what it isn't", "Real data or labelled sample data",
                 "One source per metric, never averaged"]),
     "sources.png")
