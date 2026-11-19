"""Maan pintakartat NASAn kuvista (public domain) hakemistoon assets/textures/.

Käyttö: python tools/make_earth_textures.py /polku/lähdekuviin  (pillow, numpy, opencv-python)
Lähteet:
  world.topo.200411.3x21600x10800.jpg  NASA Blue Marble Next Generation, marraskuu, maaston varjostus
      https://assets.science.nasa.gov/content/dam/science/esd/eo/images/bmng/bmng-topography/november/
  BlackMarble_2016_3km.jpg             NASA Black Marble 2016 (yövalot)
      https://assets.science.nasa.gov/content/dam/science/esd/eo/images/imagerecords/144000/144898/
  clouds8k.jpg                         Solar System Scope: 8k earth clouds (CC BY 4.0, Wikimedia Commons)

Tulokset: maa-paiva-16k.jpg (tuodaan näytönohjaimen pakkaamana), maa-paiva-8k/-4k/.webp, maa-meri.webp
(vesimaski päiväkartan väreistä), maa-yo-8k/-4k/.webp (pelkät valot: taustan maa ja kuunvalo poistetaan
morfologisella avauksella) ja maa-pilvet-8k.webp.
"""
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageFilter

Image.MAX_IMAGE_PIXELS = None
OUT = Path(__file__).resolve().parent.parent / "assets" / "textures"


def main(src: Path) -> None:
    day = Image.open(src / "world.topo.200411.3x21600x10800.jpg").convert("RGB")
    day.resize((16384, 8192), Image.LANCZOS).save(OUT / "maa-paiva-16k.jpg", quality=92, subsampling=0)
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        day.resize((w, w // 2), Image.LANCZOS).save(OUT / f"maa-paiva{suf}.webp", quality=88, method=6)
    # Vesi: tumma ja sinertävä.
    s = np.asarray(day.resize((8192, 4096), Image.LANCZOS)).astype(np.float32)
    water = ((s[..., 2] > s[..., 0] + 4) & (s.sum(axis=2) < 200)).astype(np.uint8) * 255
    mask = Image.fromarray(water).filter(ImageFilter.MedianFilter(5)).resize((4096, 2048), Image.LANCZOS)
    mask.convert("RGB").save(OUT / "maa-meri.webp", quality=90, method=6)
    # Yövalot: kirkkaus miinus paikallinen tausta (avaus 31 px poistaa valoja suuremmat sävyt).
    night = np.asarray(Image.open(src / "BlackMarble_2016_3km.jpg").convert("L").resize((8192, 4096), Image.LANCZOS))
    night = night.astype(np.float32) / 255.0
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (31, 31))
    bg = cv2.GaussianBlur(cv2.morphologyEx(night, cv2.MORPH_OPEN, kernel), (0, 0), 6)
    lights = np.clip((night - bg - 0.03) / 0.85, 0.0, 1.0)
    img = Image.fromarray((lights * 255 + 0.5).astype(np.uint8))
    for w, suf in [(8192, "-8k"), (4096, "-4k"), (2048, "")]:
        (img if w == 8192 else img.resize((w, w // 2), Image.LANCZOS)).convert("RGB").save(
            OUT / f"maa-yo{suf}.webp", quality=90, method=6)
    Image.open(src / "clouds8k.jpg").convert("L").convert("RGB").save(OUT / "maa-pilvet-8k.webp", quality=88, method=6)


if __name__ == "__main__":
    main(Path(sys.argv[1] if len(sys.argv) > 1 else "."))
