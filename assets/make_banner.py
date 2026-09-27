"""Rebuild the original PNG/SVG banner. Requires Pillow; optional font directory via DBF_FONT_DIR."""
from pathlib import Path
import math
import os
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
W, H, S = 1600, 500, 2
BG, GRID, PAPER, YELLOW, MUTED = '#151c21', '#253038', '#f3f0df', '#ffe54c', '#aab6ba'
im = Image.new('RGB', (W*S, H*S), BG)
d = ImageDraw.Draw(im)
svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">', f'<rect width="{W}" height="{H}" fill="{BG}"/>']

def line(points, fill, width=1):
    d.line([(int(x*S),int(y*S)) for x,y in points], fill=fill, width=width*S)
    svg.append('<polyline points="'+' '.join(f'{x:.2f},{y:.2f}' for x,y in points)+f'" fill="none" stroke="{fill}" stroke-width="{width}"/>')

def polygon(points, fill):
    d.polygon([(int(x*S),int(y*S)) for x,y in points], fill=fill)
    svg.append('<polygon points="'+' '.join(f'{x:.2f},{y:.2f}' for x,y in points)+f'" fill="{fill}"/>')

def text(x,y,word,size,fill,bold=False):
    fonts=Path(os.environ.get('DBF_FONT_DIR', 'C:/Windows/Fonts'))
    filename='arialbd.ttf' if bold else 'arial.ttf'
    fallback='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf' if bold else '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
    font=ImageFont.truetype(str(fonts/filename) if (fonts/filename).is_file() else fallback, size*S)
    d.text((x*S,y*S),word,font=font,fill=fill,anchor='lt')
    svg.append(f'<text x="{x}" y="{y+size*0.8}" fill="{fill}" font-family="Arial, DejaVu Sans, sans-serif" font-size="{size}" font-weight="{700 if bold else 400}">{word}</text>')

for x in range(0,W,50): line([(x,0),(x,H)],GRID)
for y in range(0,H,50): line([(0,y),(W,y)],GRID)
polygon([(0,0),(12,0),(12,H),(0,H)],YELLOW)
polygon([(58,44),(384,44),(373,80),(58,80)],YELLOW)
text(72,52,'NATIVE STRATAGEM MENUS',18,BG,True)
text(58,126,"DIVER'S",82,PAPER,True)
text(58,214,'BEST FRIEND',82,PAPER,True)
text(62,326,'POINT. CONFIRM. LIBERATE.',28,YELLOW,True)
text(62,424,'A PERSONAL HELLDIVERS 2 PROJECT',19,MUTED)

cx,cy=1260,250
for i in range(8):
    angle=-90+i*45
    pts=[]
    for radius,angles in [(205,range(-20,21)),(116,range(20,-21,-1))]:
        pts += [(cx+radius*math.cos(math.radians(angle+a)),cy+radius*math.sin(math.radians(angle+a))) for a in angles]
    polygon(pts,YELLOW if i==1 else '#38464e')
    a=math.radians(angle);x,y=cx+160*math.cos(a),cy+160*math.sin(a)
    color=BG if i==1 else PAPER
    # Simple directional marker: original schematic, no extracted game icon.
    polygon([(x,y-12),(x+12,y+2),(x+5,y+2),(x+5,y+12),(x-5,y+12),(x-5,y+2),(x-12,y+2)],color)
text(cx-54,cy-28,'DBF',46,PAPER,True)
text(cx-69,cy+32,'NO OCR NEEDED',13,MUTED)
line([(1015,42),(1035,42),(1035,62)],MUTED,2)
line([(1485,438),(1485,458),(1505,458)],MUTED,2)
svg.append('</svg>')
(ROOT/'banner.svg').write_text('\n'.join(svg)+'\n',encoding='utf-8')
im.resize((W,H),Image.Resampling.LANCZOS).save(ROOT/'banner.png',optimize=True)
print(ROOT/'banner.png')
