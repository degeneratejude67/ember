# Draws the 1024x1024 app icon: Ember, the flame mascot, glowing on a charcoal ground.
# The flame outline is the same set of Bezier segments as FlameShape in Ember/UI/Mascot.swift.
# usage: python tools/make_icon.py [out.png]
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

S = 4  # supersampling
W = 1024 * S
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
    os.path.dirname(__file__), "..", "Ember", "Resources", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")

# Unit box, y down. Each segment is (control 1, control 2, end); the path starts at START.
OUTER_START = (0.50, 1.00)
OUTER = [
    ((0.25, 1.00), (0.09, 0.86), (0.09, 0.66)),
    ((0.09, 0.48), (0.16, 0.36), (0.22, 0.24)),
    ((0.27, 0.32), (0.31, 0.40), (0.36, 0.42)),
    ((0.40, 0.22), (0.50, 0.10), (0.56, 0.00)),
    ((0.70, 0.22), (0.93, 0.42), (0.91, 0.70)),
    ((0.92, 0.90), (0.75, 1.00), (0.50, 1.00)),
]
CORE_START = (0.50, 0.98)
CORE = [
    ((0.33, 0.98), (0.24, 0.88), (0.24, 0.76)),
    ((0.24, 0.62), (0.36, 0.52), (0.51, 0.40)),
    ((0.64, 0.52), (0.76, 0.62), (0.76, 0.76)),
    ((0.76, 0.88), (0.67, 0.98), (0.50, 0.98)),
]


def bezier(start, segments, box, steps=64):
    x0, y0, w, h = box
    pts = []
    p0 = start
    for c1, c2, p3 in segments:
        for i in range(steps):
            t = i / steps
            u = 1 - t
            x = u ** 3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t ** 3 * p3[0]
            y = u ** 3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t ** 3 * p3[1]
            pts.append((x0 + x * w, y0 + y * h))
        p0 = p3
    return pts


def vertical_gradient(size, top, bottom):
    column = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        column.putpixel((0, y), tuple(round(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return column.resize(size, Image.BILINEAR)


def fill(img, pts, top, bottom):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    img.paste(vertical_gradient(img.size, top, bottom), (0, 0), mask)


img = vertical_gradient((W, W), (40, 30, 27), (14, 12, 12))

fw, fh = 560 * S, 700 * S
box = ((W - fw) / 2, 175 * S, fw, fh)
outer = bezier(OUTER_START, OUTER, box)

# warm glow behind the flame
glow = Image.new("L", (W, W), 0)
gx, gy, _, _ = box
ImageDraw.Draw(glow).ellipse((gx - 40 * S, gy + 180 * S, gx + fw + 40 * S, gy + fh + 60 * S), fill=150)
glow = glow.filter(ImageFilter.GaussianBlur(90 * S))
img.paste((255, 110, 30), (0, 0), glow)

fill(img, outer, (255, 96, 24), (255, 164, 48))
fill(img, bezier(CORE_START, CORE, box), (255, 214, 82), (255, 243, 190))

# face
d = ImageDraw.Draw(img)
eye_w, eye_h = 0.075 * fw, 0.11 * fh
for ex in (0.40, 0.60):
    cx, cy = box[0] + ex * fw, box[1] + 0.72 * fh
    d.ellipse((cx - eye_w / 2, cy - eye_h / 2, cx + eye_w / 2, cy + eye_h / 2), fill=(58, 26, 8))
    r = eye_w * 0.22
    hx, hy = cx + eye_w * 0.14, cy - eye_h * 0.2
    d.ellipse((hx - r, hy - r, hx + r, hy + r), fill=(255, 255, 255))
mx, my = box[0] + 0.50 * fw, box[1] + 0.815 * fh
mw, mh = 0.13 * fw, 0.07 * fh
d.arc((mx - mw / 2, my - mh, mx + mw / 2, my + mh * 0.4), start=20, end=160, fill=(58, 26, 8), width=round(0.018 * fw))

img = img.resize((1024, 1024), Image.LANCZOS)
os.makedirs(os.path.dirname(os.path.abspath(OUT)), exist_ok=True)
img.save(OUT, "PNG")
print(os.path.abspath(OUT))
