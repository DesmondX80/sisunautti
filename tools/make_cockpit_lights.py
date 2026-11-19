# Tunnistaa ohjaamon kuvan (assets/cockpit/ohjaamo.png) pienet värilliset valot valokartaksi
# assets/cockpit/ohjaamo_valot.png: R = vaihe, G = vilkkutapa, B = merkkivalon numero (1–6), A = peitto.
# Käyttö: python3 tools/make_cockpit_lights.py (tarvitsee numpy, opencv-python-headless ja pillow).
# Tarkistuskuva leds_vis.png kirjoitetaan nykyiseen hakemistoon.
import os, sys, numpy as np, cv2, random
from PIL import Image
im = np.array(Image.open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'cockpit', '')+'ohjaamo.png').convert('RGBA')).astype(np.float32) / 255
rgb, a = im[..., :3], im[..., 3]
H, W = a.shape
hsv = cv2.cvtColor((rgb * 255).astype(np.uint8), cv2.COLOR_RGB2HSV).astype(np.float32)
s, v = hsv[..., 1] / 255, hsv[..., 2] / 255
hue = hsv[..., 0]
blue = (hue > 95) & (hue < 130) & (s > 0.45) & (v > 0.55)
red = ((hue < 8) | (hue > 170)) & (s > 0.55) & (v > 0.5)
amber = (hue >= 8) & (hue < 25) & (s > 0.7) & (v > 0.6)
mask = blue | red | amber
mask &= a > 0.99
yy, xx = np.mgrid[0:H, 0:W]
mask &= yy > 380
# Näytöt pois
mons = [[(188,413),(361,391),(372,481),(201,517)],[(400,382),(545,375),(550,460),(407,472)],[(588,362),(808,362),(808,455),(587,453)],
        [(840,372),(997,382),(993,470),(837,458)],[(1032,392),(1218,402),(1210,517),(1025,485)],[(660,480),(727,480),(727,501),(660,501)]]
mon = np.zeros((H, W), np.uint8)
for q in mons:
    cv2.fillPoly(mon, [np.array(q, np.int32)], 1)
mon = cv2.dilate(mon, np.ones((9, 9), np.uint8))
mask &= mon == 0
# Kädet, käsivarret ja istuin pois (heijastukset eivät ole valoja).
excl = np.zeros((H, W), np.uint8)
for q in [[(150,777),(330,640),(440,560),(465,470),(570,455),(610,520),(560,610),(470,700),(430,777)],
          [(1230,777),(1100,660),(960,585),(905,560),(800,470),(875,450),(935,500),(1010,560),(1230,690),(1330,777)],
          [(400,777),(460,640),(560,575),(820,575),(920,640),(990,777)]]:
    cv2.fillPoly(excl, [np.array(q, np.int32)], 1)
mask &= excl == 0
n, lab, stats, cent = cv2.connectedComponentsWithStats(mask.astype(np.uint8), 8)
keep = []
for i in range(1, n):
    area = stats[i, cv2.CC_STAT_AREA]
    w, h = stats[i, cv2.CC_STAT_WIDTH], stats[i, cv2.CC_STAT_HEIGHT]
    if 2 <= area <= 60 and max(w, h) <= 14:
        keep.append(i)
print(len(keep), "valoa")
random.seed(7)
out = np.zeros((H, W, 4), np.uint8)
info = []
for i in keep:
    m = (lab == i)
    phase = random.random()
    r = random.random()
    kind = 0 if r < 0.55 else (1 if r < 0.82 else 2)
    cx, cy = cent[i]
    col = rgb[m].mean(0)
    info.append((i, cx, cy, stats[i, cv2.CC_STAT_AREA], col))
    out[m, 0] = int(phase * 255)
    out[m, 1] = kind
    out[m, 3] = 255
# Merkkivalot: kuusi selvintä punaista/oranssia tai sinistä valoa keskikonsolin ja sivukonsolien etuosassa.
cands = [t for t in info if (t[4][0] > t[4][2] + 0.15 or t[4][2] > t[4][0] + 0.25) and t[3] >= 5 and 150 < t[1] < 1300]
cands.sort(key=lambda t: -t[3])
for k, t in enumerate(cands[:6]):
    out[lab == t[0], 2] = k + 1
    out[lab == t[0], 1] = 0
    print("merkkivalo", k + 1, "x %.0f y %.0f ala %d väri %s" % (t[1], t[2], t[3], np.round(t[4], 2)))
# Pehmeä reuna: laajennus 1 px alfaan puolikkaalla.
dil = cv2.dilate((out[..., 3] > 0).astype(np.uint8), np.ones((3, 3), np.uint8))
for c in range(3):
    out[..., c] = cv2.dilate(out[..., c], np.ones((3, 3), np.uint8))
out[..., 3] = np.where(out[..., 3] > 0, 255, np.where(dil > 0, 110, 0))
Image.fromarray(out).save(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'assets', 'cockpit', '')+'ohjaamo_valot.png')
vis = (rgb * 255).astype(np.uint8).copy()
vis[out[..., 3] > 0] = [0, 255, 0]
for t in cands[:6]:
    cv2.circle(vis, (int(t[1]), int(t[2])), 8, (255, 0, 255), 1)
Image.fromarray(vis).crop((150, 380, 1382, 777)).save('leds_vis.png')
