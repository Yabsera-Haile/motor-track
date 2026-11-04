"""Draws the Motor Track app icon (white motorbike on near-black) for Android,
iOS and web, from the Material Icons "two_wheeler" glyph. Run from app/."""
import glob
import os
import sys

from PIL import Image, ImageDraw, ImageFont

FONT = sys.argv[1]  # materialicons-regular.otf from the Flutter SDK
GLYPH = chr(0xE689)  # Icons.two_wheeler
INK = (17, 20, 24, 255)  # Palette.ink #111418
WHITE = (255, 255, 255, 255)
BIG = 1024


def glyph_layer(canvas: int, ink_width: float) -> Image.Image:
    """White glyph on transparent, its ink `ink_width` of the canvas wide, centred."""
    img = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    font = ImageFont.truetype(FONT, BIG)
    left, top, right, bottom = font.getbbox(GLYPH)
    scale = ink_width * BIG / (right - left)
    font = ImageFont.truetype(FONT, int(BIG * scale))
    left, top, right, bottom = font.getbbox(GLYPH)
    x = (BIG - (right - left)) / 2 - left
    y = (BIG - (bottom - top)) / 2 - top
    ImageDraw.Draw(img).text((x, y), GLYPH, font=font, fill=WHITE)
    return img.resize((canvas, canvas), Image.LANCZOS)


def full(canvas: int, radius: float = 0.0, ink_width: float = 0.64) -> Image.Image:
    """The glyph on the dark background, optionally with rounded corners."""
    bg = Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))
    ImageDraw.Draw(bg).rounded_rectangle((0, 0, BIG - 1, BIG - 1), radius=int(radius * BIG), fill=INK)
    bg.alpha_composite(glyph_layer(BIG, ink_width))
    return bg.resize((canvas, canvas), Image.LANCZOS)


def save(img: Image.Image, path: str, opaque: bool = False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    (img.convert('RGB') if opaque else img).save(path, optimize=True)
    print('wrote', path, img.size[0])


res = 'android/app/src/main/res'
# Legacy launchers (Android 7 and older): rounded square.
for density, size in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    save(full(size, radius=0.22), f'{res}/mipmap-{density}/ic_launcher.png')
# Adaptive icon foreground (108 dp canvas, glyph inside the 66 dp safe circle).
for density, size in {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}.items():
    save(glyph_layer(size, 0.56), f'{res}/mipmap-{density}/ic_launcher_foreground.png')

# iOS: same sizes as the files Flutter created; no transparency allowed.
for path in glob.glob('ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png'):
    size = Image.open(path).size[0]
    save(full(size), path, opaque=True)

# Web.
for path in glob.glob('web/icons/*.png') + ['web/favicon.png']:
    size = Image.open(path).size[0]
    maskable = 'maskable' in path
    save(full(size, ink_width=0.52) if maskable else full(size, radius=0.22), path, opaque=maskable)

# A preview sheet to look at.
sheet = Image.new('RGBA', (900, 300), (244, 245, 247, 255))
sheet.alpha_composite(full(192, radius=0.22), (40, 54))
adaptive = Image.new('RGBA', (432, 432), INK)
adaptive.alpha_composite(glyph_layer(432, 0.56))
mask = Image.new('L', (432, 432), 0)
ImageDraw.Draw(mask).ellipse((0, 0, 431, 431), fill=255)
circle = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
circle.paste(adaptive, (0, 0), mask)
sheet.alpha_composite(circle.resize((192, 192), Image.LANCZOS), (300, 54))
mono = Image.new('RGBA', (432, 432), (225, 228, 240, 255))
tinted = glyph_layer(432, 0.56)
r, g, b, a = tinted.split()
tinted = Image.merge('RGBA', (r.point(lambda _: 40), g.point(lambda _: 50), b.point(lambda _: 90), a))
mono.alpha_composite(tinted)
circle2 = Image.new('RGBA', (432, 432), (0, 0, 0, 0))
circle2.paste(mono, (0, 0), mask)
sheet.alpha_composite(circle2.resize((192, 192), Image.LANCZOS), (560, 54))
sheet.save(sys.argv[2])
print('preview', sys.argv[2])
