#!/usr/bin/env python3
"""hd2ui/tools/mock_render.py -- render dump_scenes.lua display lists to PNG.

Draws the REAL geometry produced by ammo_bars (via run_lua.py capture) over a
dark stand-in background, one panel per weapon class, so the HUD composition
can be judged visually instead of by unit-test counts.

Usage:
  python run_lua.py hd2ui/tools/dump_scenes.lua > scenes.json
  python hd2ui/tools/mock_render.py scenes.json hud_mock.png [--bg image.png]
"""
import json, sys
from PIL import Image, ImageDraw, ImageFont

W, H = 720, 480            # 1:1 crop around the crosshair (override: --size WxH)
S = 1.0
if '--size' in sys.argv:
    spec = sys.argv[sys.argv.index('--size') + 1]
    W, H = (int(v) for v in spec.lower().split('x'))

def rgba(c):
    # core colors carry 0-255 alpha already (the in-game backend converts
    # them to stingray's 0-255 Color); do NOT scale again
    return (int(c[0]), int(c[1]), int(c[2]), max(0, min(255, int(c[3]))))

def font(size):
    px = max(8, int(size * S))
    for path in ('bahnschrift.ttf', 'Bahnschrift.ttf',
                 'C:/Windows/Fonts/bahnschrift.ttf', 'arialbd.ttf', 'arial.ttf'):
        try:
            return ImageFont.truetype(path, px)
        except OSError:
            pass
    return ImageFont.load_default()

def panel(cls, bg):
    # 3x supersample: PIL polygons fill boundary-inclusive, so 1px element
    # gaps vanish at 1x; at 3x they survive and survive the downsample
    Z = 3
    img = bg.resize((W * Z, H * Z), Image.LANCZOS)
    d = ImageDraw.Draw(img, 'RGBA')
    # crosshair marker (screen center)
    d.line([((W//2-10) * Z, (H//2) * Z), ((W//2+10) * Z, (H//2) * Z)], fill=(150, 255, 150, 200), width=Z)
    d.line([((W//2) * Z, (H//2-10) * Z), ((W//2) * Z, (H//2+10) * Z)], fill=(150, 255, 150, 200), width=Z)
    for t in cls['tris']:
        pts = [(t[0] - 960, t[1] - 540), (t[2] - 960, t[3] - 540), (t[4] - 960, t[5] - 540)]
        pts = [((x * S + W//2) * Z, (y * S + H//2) * Z) for x, y in pts]
        d.polygon(pts, fill=rgba(t[6:10]))
    for x in cls['texts']:
        px, py, size = x[1], x[2], x[3]
        pos = ((px - 960) * S + W//2, (py - 540) * S + H//2)
        # the scene's text y is the BASELINE (stingray Gui.text convention),
        # so anchor the PIL draw at the baseline, not the ascender top
        try:
            d.text((pos[0] * Z, pos[1] * Z), str(x[0]), font=font(size * Z),
                   fill=rgba(x[4:8]), anchor='ls')
        except TypeError:
            d.text((pos[0] * Z, pos[1] * Z), str(x[0]), font=font(size * Z), fill=rgba(x[4:8]))
    img = img.resize((W, H), Image.LANCZOS)
    d = ImageDraw.Draw(img, 'RGBA')
    # label strip
    d.rectangle([0, 0, W, 26], fill=(0, 0, 0, 180))
    d.text((8, 5), cls['name'], font=font(30), fill=(200, 255, 200, 255))
    return img

def main(path, out, bgpath=None):
    data = json.load(open(path))
    if bgpath:
        bg = Image.open(bgpath).convert('RGB').resize((W, H))
    else:
        bg = Image.new('RGB', (W, H), (52, 58, 44))
    cols = 2
    rows = (len(data['classes']) + cols - 1) // cols
    sheet = Image.new('RGB', (W * cols, H * rows))
    for i, cls in enumerate(data['classes']):
        p = panel(cls, bg)
        sheet.paste(p, ((i % cols) * W, (i // cols) * H))
    sheet.save(out)
    print(out, sheet.size)

if __name__ == '__main__':
    bgp = None
    if '--bg' in sys.argv:
        bgp = sys.argv[sys.argv.index('--bg') + 1]
    main(sys.argv[1], sys.argv[2], bgp)
