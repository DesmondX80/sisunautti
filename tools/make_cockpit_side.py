# Ohjaamon oikean sivun kuva (tools/data/ohjaamo_oikea.jpg, käyttäjän kuva) ohjaamon sivukuvaksi
# assets/cockpit/ohjaamo_sivu.png: ikkuna-alue (avaruus ja Mars) läpinäkyväksi pehmeällä reunalla.
# Vasen sivu on sama kuva peilattuna (varjostin peilaa katsesuunnan).
# Kuvan suunta ja polttoväli (Cabin.SIDE_*) on sovitettu niin, että kuvan näytön kulmat osuvat etukuvan
# kohdekameranäytön kulmiin (virhe noin 3 px): katse 47,2° oikealle, 5,1° ylös, kallistus 0,5°, polttoväli 1101 px.
# Käyttö: python3 tools/make_cockpit_side.py (tarvitsee pillow ja numpy).
import os, numpy as np
from PIL import Image, ImageDraw, ImageFilter
root = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
im = Image.open(os.path.join(root, 'tools', 'data', 'ohjaamo_oikea.jpg')).convert('RGB')
W, H = im.size
# Ikkunan ääriviiva kuvassa (pikselit): yläkehys, pilarin puoleinen sisälasi ja kojelaudan yläreuna.
WINDOW = [(0, 257), (100, 268), (200, 283), (300, 301), (350, 312), (368, 321), (378, 334), (400, 344), (418, 357),
	(427, 374), (426, 520), (418, 580), (402, 636), (382, 682), (362, 703), (336, 711), (300, 707), (200, 704),
	(100, 702), (40, 699), (28, 690), (0, 682)]
S = 4
mask = Image.new('L', (W * S, H * S), 255)
ImageDraw.Draw(mask).polygon([(x * S, y * S) for x, y in WINDOW], fill=0)
mask = mask.resize((W, H), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6))
out = im.copy()
out.putalpha(mask)
out.save(os.path.join(root, 'assets', 'cockpit', 'ohjaamo_sivu.png'), optimize=True)
print('ohjaamo_sivu.png', W, H)
