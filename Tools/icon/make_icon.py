#!/usr/bin/env python3
"""
Generates Nodogram's app icon.

Original mark, deliberately unlike Telegram's: NO paper plane and NO blue
circle (see Documentation/LEGAL_AND_LICENSES.md §5). The concept is three
offset, stacked message layers — reading as retained history, which is
Nodogram's actual differentiator.

Drawn at 4x and downsampled so the curves stay clean at every icon size.
"""
import os
import sys
from PIL import Image, ImageDraw

# Nodogram's slate-indigo accent, matching Theme.accent (0.36, 0.40, 0.78).
ACCENT_TOP = (92, 102, 199)
ACCENT_BOTTOM = (68, 76, 164)
LAYER_MID = (255, 255, 255, 235)
LAYER_BACK = (255, 255, 255, 150)
LAYER_FAR = (255, 255, 255, 80)


def rounded_rect_mask(size, radius, supersample=4):
    """macOS-style squircle approximation via a high-res rounded rectangle."""
    big = size * supersample
    mask = Image.new("L", (big, big), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, big - 1, big - 1], radius=radius * supersample, fill=255)
    return mask.resize((size, size), Image.LANCZOS)


def vertical_gradient(size, top, bottom):
    grad = Image.new("RGB", (1, size))
    for y in range(size):
        t = y / max(size - 1, 1)
        grad.putpixel((0, y), tuple(
            int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)
        ))
    return grad.resize((size, size), Image.BICUBIC)


def bubble(draw, box, radius, fill, tail=False):
    """A message bubble. Only the front layer gets a tail; giving the stacked
    layers tails too reads as spikes rather than depth."""
    x0, y0, x1, y1 = box
    draw.rounded_rectangle(box, radius=radius, fill=fill)
    if tail:
        points = [
            (x0 + radius * 0.60, y1 - radius * 0.20),
            (x0 + radius * 0.05, y1 + radius * 0.80),
            (x0 + radius * 1.55, y1 - radius * 0.05),
        ]
        draw.polygon(points, fill=fill)


def render(size):
    ss = 4
    big = size * ss
    canvas = Image.new("RGBA", (big, big), (0, 0, 0, 0))

    # Background: gradient inside a squircle.
    bg = vertical_gradient(big, ACCENT_TOP, ACCENT_BOTTOM).convert("RGBA")
    bg.putalpha(rounded_rect_mask(big, int(big * 0.225), supersample=1))
    canvas.alpha_composite(bg)

    layer = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)

    # Three stacked bubbles, offset up-left, back to front.
    w, h = big * 0.50, big * 0.235
    r = big * 0.072
    cx, cy = big * 0.50, big * 0.585

    for dx, dy, scale, fill, has_tail in (
        (-big * 0.085, -big * 0.175, 0.86, LAYER_FAR, False),
        (-big * 0.042, -big * 0.088, 0.93, LAYER_BACK, False),
        (0.0, 0.0, 1.0, LAYER_MID, True),
    ):
        lw, lh = w * scale, h * scale
        box = [cx - lw / 2 + dx, cy - lh / 2 + dy, cx + lw / 2 + dx, cy + lh / 2 + dy]
        bubble(d, box, r * scale, fill, tail=has_tail)

    canvas.alpha_composite(layer)
    return canvas.resize((size, size), Image.LANCZOS)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "Tools/icon/Nodogram.iconset"
    os.makedirs(out, exist_ok=True)
    # The sizes iconutil expects for a complete .icns.
    specs = [
        (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
    ]
    cache = {}
    for px, name in specs:
        if px not in cache:
            cache[px] = render(px)
        cache[px].save(os.path.join(out, name))
    print(f"wrote {len(specs)} images to {out}")


if __name__ == "__main__":
    main()
