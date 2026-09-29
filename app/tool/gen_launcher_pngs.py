"""Legacy launcher PNGs (mipmap-*dpi) for the Airlog ring mark.

minSdk 26 always uses the adaptive icon (mipmap-anydpi-v26); these are the
fallback bitmaps that replace Flutter's default logo. Geometry matches
res/drawable/ic_launcher_foreground.xml (108-unit canvas, ring r=22,
stroke 8, 270 degrees clockwise from 12 o'clock) cropped to the 72-unit
visible area of an adaptive icon.

    python tool/gen_launcher_pngs.py
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "android/app/src/main/res"
BG = (0x0B, 0x0C, 0x0E, 255)
RING = (0x35, 0xD0, 0x7F, 255)
TRACK = (0x35, 0xD0, 0x7F, 0x4D)
SIZES = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
SS = 8  # supersampling


def mark(px: int, round_icon: bool) -> Image.Image:
    big = px * SS
    u = big / 72.0  # one adaptive-canvas unit (visible 72 of 108)
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if round_icon:
        d.ellipse([0, 0, big - 1, big - 1], fill=BG)
    else:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius=int(big * 0.22), fill=BG)
    c, r, w = 36 * u, 22 * u, 8 * u
    box = [c - r - w / 2, c - r - w / 2, c + r + w / 2, c + r + w / 2]
    # Track: full circle.
    track = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(track).arc(box, 0, 360, fill=TRACK, width=int(w))
    img = Image.alpha_composite(img, track)
    d = ImageDraw.Draw(img)
    # PIL angles: 0 = 3 o'clock, clockwise. 12 o'clock = -90 -> 180 (9 o'clock).
    d.arc(box, -90, 180, fill=RING, width=int(w))
    for ang in (-90, 180):  # round caps
        x = c + r * math.cos(math.radians(ang))
        y = c + r * math.sin(math.radians(ang))
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=RING)
    return img.resize((px, px), Image.LANCZOS)


def main() -> None:
    for density, px in SIZES.items():
        out = RES / f"mipmap-{density}"
        out.mkdir(parents=True, exist_ok=True)
        mark(px, False).save(out / "ic_launcher.png")
        mark(px, True).save(out / "ic_launcher_round.png")
        print(out / "ic_launcher.png", px)


if __name__ == "__main__":
    main()
