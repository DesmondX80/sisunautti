"""Marsin pintakartat USGS:n globaaleista mosaiikeista (public domain) hakemistoon assets/textures/.

Käyttö: uv run --with pillow --with numpy --with opencv-python-headless --with tifffile --with imagecodecs \
            python tools/make_mars_textures.py /polku/lähdekuviin
Lähteet (https://planetarymaps.usgs.gov/mosaic/, USGS Astrogeology):
  Mars_Viking_ClrMosaic_global_925m.tif       Viking-luotainten värimosaiikki, 925 m/px (23 040 × 11 520)
  Mars_MGS_MOLA_DEM_mosaic_global_463m.tif    Mars Global Surveyorin laserkorkeusmittari (MOLA), 463 m/px, metreinä

Tulokset: mars-16k.jpg (tuodaan näytönohjaimen pakkaamana), mars-8k.webp, mars-4k.webp, mars.webp ja
mars-pinta-8k.webp, mars-pinta-4k.webp, mars-pinta.webp (kohokuvio kuten Kuussa, ks. make_moon_textures.py).
"""
import sys
from pathlib import Path

import cv2
import numpy as np
import tifffile
from PIL import Image

from make_moon_textures import surface_map

Image.MAX_IMAGE_PIXELS = None
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
R_M = 3389.5e3
# Paikallisen korkeuden alue (m): kanjonit ja tulivuorten rinteet ovat Kuun kraattereita korkeampia.
HEIGHT_RANGE = 7000.0


def halve(a: np.ndarray, rows: int = 2048) -> np.ndarray:
    """Puolittaa kuvan 2 × 2 -keskiarvoilla lohko kerrallaan (muistikartasta, ei koko kuvaa muistiin)."""
    h, w = a.shape[0] // 2, a.shape[1] // 2
    out = np.empty((h, w) + a.shape[2:], np.float32)
    for y in range(0, h, rows):
        b = np.asarray(a[2 * y:2 * min(y + rows, h)], dtype=np.float32)
        out[y:y + b.shape[0] // 2] = 0.25 * (b[0::2, 0::2] + b[1::2, 0::2] + b[0::2, 1::2] + b[1::2, 1::2])
    return out


# Väripaletti kirkkauden mukaan (sRGB): Vikingin värimosaiikin tummat alueet ovat sinertäviä (värityksen virhe),
# todellisuudessa ne ovat tumman ruskeanharmaita; kirkkaat alueet voinkeltaisen oransseja ja napalakit vaaleita.
PALETTE = [(0.0, (0.07, 0.05, 0.04)), (0.18, (0.29, 0.2, 0.15)), (0.36, (0.54, 0.35, 0.23)),
           (0.56, (0.77, 0.53, 0.35)), (0.76, (0.9, 0.76, 0.62)), (1.0, (0.98, 0.97, 0.96))]


def grade(rgb: np.ndarray, rows: int = 1024) -> np.ndarray:
    """Värit paletista kirkkauden mukaan (kirkkaus venytetään 0,5–99,8 %:n välille); 15 % alkuperäistä värisävyä.
    Lohko kerrallaan, jotta 16k-kuva mahtuu muistiin."""
    w = np.array([0.3, 0.59, 0.11], np.float32)
    lo, hi = np.percentile(rgb[::8, ::8].astype(np.float32) @ w / 255.0, [0.5, 99.8])
    xs = [p[0] for p in PALETTE]
    out = np.empty_like(rgb)
    for y in range(0, rgb.shape[0], rows):
        f = rgb[y:y + rows].astype(np.float32) / 255.0
        lum = f @ w
        t = np.clip((lum - lo) / (hi - lo), 0.0, 1.0)
        g = np.stack([np.interp(t, xs, [p[1][c] for p in PALETTE]) for c in range(3)], axis=-1).astype(np.float32)
        g += 0.15 * (f - lum[..., None])
        out[y:y + rows] = (np.clip(g, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    return out


def main(src: Path) -> None:
    color = tifffile.memmap(src / "Mars_Viking_ClrMosaic_global_925m.tif")
    print("väri", color.shape, color.dtype)
    if color.ndim == 3 and color.shape[0] in (3, 4):  # tasoittain tallennettu (kanava, rivi, sarake)
        color = np.moveaxis(color, 0, -1)
    rgb = cv2.resize(np.ascontiguousarray(color[..., :3]), (16384, 8192), interpolation=cv2.INTER_AREA)
    img = Image.fromarray(grade(rgb))
    img.save(OUT / "mars-16k.jpg", quality=92, subsampling=0)
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        img.resize((w, w // 2), Image.LANCZOS).save(OUT / f"mars{suf}.webp", quality=90, method=6)
    del img, rgb, color
    dem = tifffile.memmap(src / "Mars_MGS_MOLA_DEM_mosaic_global_463m.tif")
    print("korkeus", dem.shape, dem.dtype)
    dem = cv2.resize(halve(dem), (16384, 8192), interpolation=cv2.INTER_AREA) / 1000.0
    print("korkeus km", float(dem.min()), float(dem.max()))
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        surface_map(dem, w, R_M, HEIGHT_RANGE).save(OUT / f"mars-pinta{suf}.webp", quality=95, method=6)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
