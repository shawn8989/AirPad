#!/usr/bin/env python3
"""Frame raw device captures into App Store screenshots.

Apple accepts a bare screenshot, but a framed one with a caption is what makes
a product page legible at thumbnail size -- which is how most people see it.
This does the same job as docs/screenshots/frame.html (drop a file in, get a
sized PNG out), without a browser, so CI can run it.

Output sizes are the two Apple asks for on iPhone. A capture of any resolution
is scaled to fit; it is never stretched.

    python3 scripts/frame-screenshots.py <raw-dir> <out-dir>
"""
import sys, pathlib
from PIL import Image, ImageDraw, ImageFont

# Apple's required iPhone sizes. 6.5" is what App Store Connect currently
# accepts for this app; 6.9" is included because larger uploads are scaled
# down cleanly and future device sizes tend to start from the biggest.
SIZES = [(1284, 2778, "6.5"), (1320, 2868, "6.9")]

# Filename stem -> caption. Anything not listed still gets framed, captionless,
# rather than being silently dropped.
CAPTIONS = {
    "01-trackpad":   "Your Mac, in your pocket",
    "02-livescreen": "See your Mac. Touch what you see.",
    "03-handmouse":  "Control it with your hands",
    "04-desktops":   "Jump to any window, instantly",
    "05-gestures":   "Record your own gestures",
    "06-media":      "Remote for everything",
    "paywall":       "One purchase. Yours forever.",
}

BG_TOP, BG_BOTTOM = (31, 43, 77), (76, 47, 107)   # matches frame.html
FG = (255, 255, 255)


def load_font(px):
    """Pick whatever real font this machine has; fall back to the bitmap one."""
    for path in ("/System/Library/Fonts/SFNS.ttf",
                 "/System/Library/Fonts/Helvetica.ttc",
                 "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            continue
    return ImageFont.load_default()


def gradient(w, h):
    base = Image.new("RGB", (1, h))
    for y in range(h):
        t = y / max(h - 1, 1)
        base.putpixel((0, y), tuple(
            round(BG_TOP[i] + (BG_BOTTOM[i] - BG_TOP[i]) * t) for i in range(3)))
    return base.resize((w, h))


def wrap(draw, text, font, max_w):
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) > max_w and line:
            lines.append(line)
            line = word
        else:
            line = trial
    if line:
        lines.append(line)
    return lines


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([(0, 0), img.size], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def frame(shot, caption, w, h):
    canvas = gradient(w, h)
    draw = ImageDraw.Draw(canvas)

    y = round(h * 0.075)
    if caption:
        size = round(w * 0.062)
        font = load_font(size)
        for line in wrap(draw, caption, font, w - round(w * 0.16)):
            y += size
            draw.text((w / 2, y), line, font=font, fill=FG, anchor="ms")
            y += round(size * 0.18)

    avail_top = y + round(h * 0.045)
    avail_h = h - avail_top - round(h * 0.05)
    max_w = round(w * 0.80)
    ratio = min(max_w / shot.width, avail_h / shot.height)
    dw, dh = round(shot.width * ratio), round(shot.height * ratio)
    device = rounded(shot.resize((dw, dh), Image.LANCZOS), round(dw * 0.055))

    canvas.paste(device, ((w - dw) // 2, avail_top), device)
    return canvas


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    raw, out = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    shots = sorted(p for p in raw.glob("*.png"))
    if not shots:
        sys.exit(f"No PNGs in {raw}")

    for path in shots:
        shot = Image.open(path).convert("RGB")
        caption = CAPTIONS.get(path.stem, "")
        for w, h, label in SIZES:
            dest = out / f"{path.stem}-{label}-{w}x{h}.png"
            frame(shot, caption, w, h).save(dest)
            print(f"  {dest.name}")
    print(f"\n{len(shots)} capture(s) -> {len(shots) * len(SIZES)} framed image(s) in {out}")


if __name__ == "__main__":
    main()
