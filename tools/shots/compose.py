"""Frames the raw renders (<out>/black, <out>/white) into the images the
README, the site and the social preview use: docs/cover.png and
docs/screenshots/*. Everything is drawn at 2x; the cover is saved at 1x.

usage: SHOTS_CACHE=<fonts and logo> compose.py <out dir> <docs dir>
Run through shots.sh, which fills the cache.
"""
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = Path(sys.argv[1])
DOCS = Path(sys.argv[2])
SHOTS = DOCS / "screenshots"
SHOTS.mkdir(parents=True, exist_ok=True)

CACHE = Path(os.environ["SHOTS_CACHE"])
# The site's own typefaces.
FONTS = {
    "display": str(CACHE / "funnel-600.ttf"),
    "body": str(CACHE / "geist-400.ttf"),
    "mono": str(CACHE / "mono-400.ttf"),
    "mono-medium": str(CACHE / "mono-500.ttf"),
}
AMBER = (255, 176, 32)
rng = np.random.default_rng(11)


def font(kind, size):
    return ImageFont.truetype(FONTS[kind], size)


def load(theme, name):
    return Image.open(OUT / theme / f"{name}.png").convert("RGBA")


def trim(img, pad=0):
    box = img.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
    x0, y0, x1, y1 = box
    return img.crop((max(0, x0 - pad), max(0, y0 - pad), min(img.width, x1 + pad), min(img.height, y1 + pad)))


def grain(img, amount):
    arr = np.asarray(img).astype(np.int16)
    noise = rng.normal(0, amount, arr.shape[:2])[..., None]
    arr[..., :3] = np.clip(arr[..., :3] + noise, 0, 255)
    return Image.fromarray(arr.astype(np.uint8), img.mode)


def gradient(w, h, top, bottom, glows=()):
    """A vertical gradient with soft radial glows: (x, y, radius, colour, strength)."""
    t = np.linspace(0, 1, h)[:, None, None]
    top, bottom = np.array(top, float), np.array(bottom, float)
    arr = np.broadcast_to(top * (1 - t) + bottom * t, (h, w, 3)).copy()
    yy, xx = np.mgrid[0:h, 0:w]
    for gx, gy, radius, colour, strength in glows:
        d = np.sqrt((xx - gx * w) ** 2 + (yy - gy * h) ** 2) / (radius * max(w, h))
        k = np.clip(1 - d, 0, 1) ** 2.2 * strength
        arr = arr * (1 - k[..., None]) + np.array(colour, float) * k[..., None]
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8)).convert("RGBA")


def screen_bg(w, h, theme):
    if theme == "black":
        img = gradient(w, h, (30, 44, 46), (9, 10, 13),
                       [(0.85, 0.05, 0.9, (58, 82, 80), 0.55), (0.1, 1.0, 0.8, (38, 24, 12), 0.35)])
    else:
        img = gradient(w, h, (214, 224, 223), (238, 240, 242),
                       [(0.85, 0.05, 0.9, (246, 248, 247), 0.6), (0.1, 1.0, 0.8, (236, 222, 205), 0.35)])
    return grain(img, 3.2)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, fill=255)
    out = img.copy()
    out.putalpha(Image.fromarray(np.minimum(np.asarray(mask), np.asarray(img.getchannel("A")))))
    return out


def outline(img, radius, colour=(255, 255, 255, 22), width=2):
    over = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(over).rounded_rectangle((0, 0, img.width - 1, img.height - 1), radius, outline=colour, width=width)
    return Image.alpha_composite(img, over)


def shadow_under(canvas, item, x, y, blur=40, opacity=0.55, dy=18):
    alpha = item.getchannel("A").point(lambda a: int(a * opacity))
    sh = Image.new("RGBA", (item.width + blur * 4, item.height + blur * 4), (0, 0, 0, 0))
    black = Image.new("RGBA", item.size, (0, 0, 0, 255))
    black.putalpha(alpha)
    sh.alpha_composite(black, (blur * 2, blur * 2))
    sh = sh.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(sh, (x - blur * 2, y - blur * 2 + dy))
    canvas.alpha_composite(item, (x, y))


def screen_with_notch(render, theme, pad=(0, 70, 90, 70), radius=36):
    """The notch welded to the left edge of a small 'screen'."""
    left, top, right, bottom = pad
    w, h = render.width + left + right, render.height + top + bottom
    tile = screen_bg(w, h, theme)
    tile.alpha_composite(render, (left, top))
    tile = rounded(tile, radius)
    return outline(tile, radius, (255, 255, 255, 26) if theme == "black" else (0, 0, 0, 22))


def screen_with_strip(render, theme, pad=(90, 0, 90, 80), radius=36):
    """The compact strip hanging from the top edge."""
    left, top, right, bottom = pad
    w, h = render.width + left + right, render.height + top + bottom
    tile = screen_bg(w, h, theme)
    tile.alpha_composite(render, (left, top))
    return outline(rounded(tile, radius), radius)


def floating(render, theme, pad=110, radius=40):
    """A sheet (settings, usage) floating over the screen, with its shadow."""
    w, h = render.width + 2 * pad, render.height + 2 * pad
    tile = screen_bg(w, h, theme)
    shadow_under(tile, render, pad, pad, blur=48, opacity=0.7 if theme == "black" else 0.25)
    return outline(rounded(tile, radius), radius)


def tracked(draw, xy, text, f, fill, tracking, anchor="lm"):
    """Text with letter-spacing, like the site's small caps tags."""
    widths = [draw.textlength(ch, font=f) for ch in text]
    total = sum(widths) + tracking * (len(text) - 1)
    x, y = xy
    if anchor[0] == "m":
        x -= total / 2
    for ch, w in zip(text, widths):
        draw.text((x, y), ch, font=f, fill=fill, anchor="l" + anchor[1])
        x += w + tracking
    return total


def label(draw, xy, text, size=26, fill=(160, 164, 170), kind="mono-medium", anchor="mm", tracking=6):
    tracked(draw, xy, text, font(kind, size), fill, tracking, anchor)


def row(tiles, gap=48, pad=0, bg=None, captions=None, caption_h=0):
    w = sum(t.width for t in tiles) + gap * (len(tiles) - 1) + 2 * pad
    h = max(t.height for t in tiles) + 2 * pad + caption_h
    canvas = Image.new("RGBA", (w, h), bg or (0, 0, 0, 0))
    x = pad
    draw = ImageDraw.Draw(canvas)
    for i, t in enumerate(tiles):
        canvas.alpha_composite(t, (x, pad))
        if captions:
            label(draw, (x + t.width // 2, pad + max(tt.height for tt in tiles) + caption_h // 2 + 4), captions[i].upper())
        x += t.width + gap
    return canvas


def save(img, name, max_width=None):
    if max_width and img.width > max_width:
        img = img.resize((max_width, round(img.height * max_width / img.width)), Image.LANCZOS)
    path = SHOTS / name if not name.startswith("../") else DOCS / name[3:]
    img.save(path, optimize=True)
    print(f"{path.relative_to(DOCS.parent)}  {img.width}x{img.height}", file=sys.stderr)


# ---------------- the notch and its card ----------------
card = trim(load("black", "notch-card"))
sessions = trim(load("black", "notch-sessions"))
account = trim(load("black", "notch-account"))
save(screen_with_notch(sessions, "black"), "sessions.png")
save(screen_with_notch(account, "black"), "accounts.png")

# ---------------- black and white, side by side ----------------
light_card = trim(load("white", "notch-card"))
height = max(card.height, light_card.height)
pair = row([screen_with_notch(card, "black", pad=(0, 70 + (height - card.height) // 2, 90, 70 + (height - card.height + 1) // 2)),
            screen_with_notch(light_card, "white", pad=(0, 70 + (height - light_card.height) // 2, 90, 70 + (height - light_card.height + 1) // 2))],
           gap=40)
save(pair, "themes.png")

# ---------------- three looks ----------------
# The body ends at x=141 in the 2x render; past it is only the card's tail.
notch_only = card.crop((0, 0, 141, card.height))
notch_only = trim(notch_only)
aura = trim(load("black", "aura"))
compact = trim(load("black", "compact"))
tall = max(notch_only.height, aura.height)


def edge_tile(render, width):
    pad_v = (tall - render.height) // 2
    return screen_with_notch(render, "black", pad=(0, 70 + pad_v, width - render.width, 70 + tall - render.height - pad_v))


looks = [edge_tile(notch_only, 330), edge_tile(aura, 330)]
strip_tile = screen_with_strip(compact, "black", pad=(70, 0, 70, looks[0].height - compact.height))
looks.append(strip_tile)
save(row(looks, gap=40, captions=["classic", "aura", "compact"], caption_h=90), "styles.png")

# ---------------- sheets ----------------
# Where the heatmap card ends in the 2x usage render, found by scanning for
# the sheet's own background between cards.
def deck_cut(img):
    arr = np.asarray(img.convert("RGB")).astype(int)
    column = arr[:, 60]
    bg = arr[40, 60]
    rows = [y for y in range(900, 1500) if abs(column[y] - bg).max() <= 3 and abs(arr[y, img.width // 2] - bg).max() <= 3]
    return (rows[0] + 6) if rows else 1300


DECK_CUT = deck_cut(load("black", "usage-work"))
save(floating(load("black", "settings-providers"), "black"), "settings.png")
usage = load("black", "usage")
save(floating(usage, "black", pad=90), "usage.png")
save(floating(load("black", "usage-work").crop((0, 0, usage.width, DECK_CUT)), "black", pad=90), "usage-deck.png")


# ---------------- the cover, 1280x640 (drawn at 2x, saved at 1x) ----------------
def cover():
    W, H = 2560, 1280
    c = gradient(W, H, (8, 9, 11), (4, 4, 5), [(0.78, 0.45, 0.55, (26, 34, 36), 0.9), (0.95, 1.0, 0.5, (40, 26, 8), 0.5)])
    c = grain(c, 2.6)
    d = ImageDraw.Draw(c)
    # faint gauge arcs behind the screen, the logo's shape made large
    arcs = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ad = ImageDraw.Draw(arcs)
    cx, cy = 1830, 1420
    for i, r in enumerate(range(520, 1500, 150)):
        ad.arc((cx - r, cy - r, cx + r, cy + r), 180, 360, fill=(255, 255, 255, 14 - i), width=3)
    c.alpha_composite(arcs)

    logo = Image.open(CACHE / "flare-512.png").convert("RGBA").resize((136, 136), Image.LANCZOS)
    c.alpha_composite(logo, (150, 150))
    d.text((318, 176), "QUICKSHELL / HYPRLAND", font=font("mono-medium", 34), fill=(236, 237, 239))
    tracked(d, (320, 248), "AI USAGE NOTCH", font("mono", 24), (128, 132, 138), 7)

    d.text((142, 380), "flare.", font=font("display", 250), fill=(244, 244, 245))
    # the amber rule under the title: the logo's gauge, read left to right
    d.rounded_rectangle((152, 690, 312, 700), 5, fill=AMBER)
    d.rounded_rectangle((330, 690, 390, 700), 5, fill=(90, 92, 98))
    d.rounded_rectangle((408, 690, 428, 700), 5, fill=(60, 62, 66))

    body = font("body", 50)
    d.text((148, 770), "Your AI coding limits,", font=body, fill=(200, 202, 206))
    d.text((148, 836), "on the edge of the screen.", font=body, fill=(200, 202, 206))

    x = 148
    for chip in ["6 PROVIDERS", "MULTI-LOGIN", "LOCAL-FIRST"]:
        f = font("mono-medium", 24)
        tw = sum(d.textlength(ch, font=f) for ch in chip) + 4 * (len(chip) - 1)
        d.rounded_rectangle((x, 960, x + tw + 84, 1032), 36, fill=(22, 23, 26), outline=(255, 255, 255, 30), width=2)
        d.ellipse((x + 28, 990, x + 40, 1002), fill=AMBER if chip == "6 PROVIDERS" else (200, 202, 206))
        tracked(d, (x + 58, 996), chip, f, (222, 224, 227), 4)
        x += tw + 84 + 22
    tracked(d, (150, 1162), "OPEN SOURCE · RUST · QML · MIT", font("mono", 22), (110, 114, 120), 6)

    # the widget itself, on a small screen at the right
    shot = screen_with_notch(sessions, "black", pad=(0, 54, 60, 54), radius=40)
    scale = 1060 / shot.height
    shot = shot.resize((round(shot.width * scale), 1060), Image.LANCZOS)
    shadow_under(c, shot, W - shot.width - 150, (H - shot.height) // 2, blur=60, opacity=0.8, dy=24)
    return c.resize((1280, 640), Image.LANCZOS)


save(cover(), "../cover.png")
