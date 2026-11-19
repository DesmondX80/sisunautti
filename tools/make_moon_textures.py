"""Kuun pintakartat NASAn CGI Moon Kitistä (public domain) hakemistoon assets/textures/.

Käyttö: uv run --with pillow --with numpy --with opencv-python-headless --with tifffile \
            python tools/make_moon_textures.py /polku/lähdekuviin
Lähteet (https://svs.gsfc.nasa.gov/4720/, NASA Scientific Visualization Studio):
  lroc_color_poles_16k.tif  LRO:n laajakulmakameran (WAC) värimosaiikki napoineen, 16 384 × 8 192 px
  ldem_64.tif               LRO:n laserkorkeusmittarin (LOLA) korkeusmalli, 64 px/aste (23 040 × 11 520, km)

Tulokset:
  kuu-16k.jpg, kuu-8k.webp, kuu-4k.webp, kuu.webp   värikartta (16k tuodaan näytönohjaimen pakkaamana)
  kuu-pinta-8k.webp, kuu-pinta-4k.webp, kuu-pinta.webp
      R, G = pinnan normaalin itä- ja eteläkomponentti (0,5 + 0,5 n), kartan sarakkeiden ja rivien suuntaan
      B    = paikallinen korkeus (ylipäästö, ±HEIGHT_RANGE m) varjojen laskemiseen varjostimessa
"""
import sys
from pathlib import Path

import cv2
import numpy as np
import tifffile
from PIL import Image

Image.MAX_IMAGE_PIXELS = None
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"
R_M = 1737.4e3
# Paikallisen korkeuden alue (m) ja ylipäästön leveys (km): varjot lasketaan enintään noin 60 km:n päähän.
HEIGHT_RANGE = 4000.0
HIGHPASS_KM = 120.0


def surface_map(dem_km: np.ndarray, w: int) -> Image.Image:
    h = w // 2
    dem = cv2.resize(dem_km, (w, h), interpolation=cv2.INTER_AREA).astype(np.float64) * 1000.0
    lat = (0.5 - (np.arange(h) + 0.5) / h) * np.pi
    dx = np.maximum(np.cos(lat), 0.02)[:, None] * 2.0 * np.pi * R_M / w  # sarakkeen leveys metreinä
    dy = np.pi * R_M / h
    # Kaltevuudet sarakkeiden (itä) ja rivien (etelä) suuntaan; pituuspiirin suunnassa kartta jatkuu ympäri.
    gx = (np.roll(dem, -1, axis=1) - np.roll(dem, 1, axis=1)) / (2.0 * dx)
    pad = np.pad(dem, ((1, 1), (0, 0)), mode="edge")
    gy = (pad[2:] - pad[:-2]) / (2.0 * dy)
    inv = 1.0 / np.sqrt(gx * gx + gy * gy + 1.0)
    nx = -gx * inv
    ny = -gy * inv
    # Ylipäästö: korkeus suhteessa ympäristöön (Gaussin sumennus), jotta 8 bittiä riittää.
    sigma = HIGHPASS_KM * 1000.0 / dy
    base = cv2.GaussianBlur(dem, (0, 0), sigma, borderType=cv2.BORDER_REFLECT)
    local = np.clip((dem - base) / HEIGHT_RANGE, -1.0, 1.0)
    rgb = np.stack([nx, ny, local], axis=-1) * 0.5 + 0.5
    return Image.fromarray((rgb * 255.0 + 0.5).clip(0, 255).astype(np.uint8))


def main(src: Path) -> None:
    color = Image.fromarray(tifffile.imread(src / "lroc_color_poles_16k.tif")[..., :3])
    print("väri", color.size)
    color.save(OUT / "kuu-16k.jpg", quality=92, subsampling=0)
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        color.resize((w, w // 2), Image.LANCZOS).save(OUT / f"kuu{suf}.webp", quality=90, method=6)
    del color
    dem = tifffile.memmap(src / "ldem_64.tif")
    dem = cv2.resize(np.asarray(dem), (16384, 8192), interpolation=cv2.INTER_AREA)
    print("korkeus", dem.shape, float(dem.min()), float(dem.max()))
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        surface_map(dem, w).save(OUT / f"kuu-pinta{suf}.webp", quality=95, method=6)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
