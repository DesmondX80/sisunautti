"""Lennonjohdon puheäänet: kaikki repliikit samalla Kokoro-TTS-äänellä (am_michael, Apache 2.0), radiosuodatettuina.

Lähtölaskennan luvut, laukaisu, tornin ohitus, Max Q, vaiheen erotus, toisen vaiheen sytytys sekä lennon vaiheiden
kuulutukset. Lennon vaiheiden kuulutuksissa Quindar-piippaukset (2525 Hz alussa, 2475 Hz lopussa) kuten Apollossa.
Tulos: assets/sound/voice/<nimi>.ogg (22 050 Hz mono Vorbis).

Ajo (malli ~330 Mt, lataa https://github.com/thewh1teagle/kokoro-onnx/releases/tag/model-files-v1.0):
    uv venv && uv pip install kokoro-onnx soundfile scipy numpy
    .venv/bin/python tools/make_voice.py <kansio, jossa kokoro-v1.0.onnx ja voices-v1.0.bin>
"""
import sys
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro_onnx import Kokoro
from scipy.signal import butter, resample_poly, sosfilt

VOICE = "am_michael"
RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "sound" / "voice"
# Luvut ilman välimerkkiä: "Six." ääntyy Kokorolla epäselvästi.
NUMBERS = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
# nimi → (teksti, Quindar-piippaukset)
LINES = {f"count{i + 1}": (w, False) for i, w in enumerate(NUMBERS)}
LINES |= {
    "liftoff": ("And liftoff! We have liftoff.", False),
    "tower": ("Tower cleared.", False),
    "maxq": ("Vehicle is passing through max Q.", False),
    "staging": ("Main engine cutoff. Booster separation confirmed.", False),
    "stage2": ("Second stage ignition.", False),
    "orbit": ("Orbit insertion confirmed.", True),
    "depart": ("Departure burn confirmed. We are on our way.", True),
    "soi": ("Entering sphere of influence.", True),
    "arrive": ("Arrival confirmed.", True),
    "capture": ("Capture burn complete. Orbit confirmed.", True),
    "flyby": ("No capture. Continuing on flyby trajectory.", True),
}


def trim(x: np.ndarray, rate: int) -> np.ndarray:
    """Hiljaisuus pois alusta ja lopusta (sibilanttien vuoksi matala kynnys ja 60 ms marginaali)."""
    on = np.flatnonzero(np.abs(x) > 0.004 * np.abs(x).max())
    pad = int(0.06 * rate)
    return x[max(0, on[0] - pad):on[-1] + pad]


def radio(x: np.ndarray) -> np.ndarray:
    """Lennonjohdon radio: kaista 300–3800 Hz, pehmeä kompressio ja hiljainen kohina."""
    x = sosfilt(butter(4, [300, 3800], btype="band", fs=RATE, output="sos"), x)
    x = np.tanh(2.2 * x / np.abs(x).max()) / np.tanh(2.2)
    rng = np.random.default_rng(7)
    hiss = sosfilt(butter(2, [400, 4000], btype="band", fs=RATE, output="sos"), rng.standard_normal(x.size))
    return x + hiss * 0.012


def tone(hz: float, length: float) -> np.ndarray:
    t = np.arange(int(length * RATE)) / RATE
    return np.sin(2 * np.pi * hz * t) * np.minimum(1, t / 0.005) * np.minimum(1, (length - t) / 0.02) * 0.35


def main() -> None:
    models = Path(sys.argv[1])
    tts = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"))
    OUT.mkdir(parents=True, exist_ok=True)
    gap = np.zeros(int(0.12 * RATE))
    for name, (text, quindar) in LINES.items():
        x, rate = tts.create(text, voice=VOICE, speed=1.0, lang="en-us")
        x = resample_poly(trim(np.asarray(x, dtype=np.float64), rate), RATE, rate)
        x = radio(x) * 0.8
        if quindar:
            x = np.concatenate([tone(2525, 0.25), gap, x, gap, tone(2475, 0.25)])
        sf.write(OUT / f"{name}.ogg", x.astype(np.float32), RATE, format="OGG", subtype="VORBIS")
        print(f"{name}: {x.size / RATE:.2f} s")


if __name__ == "__main__":
    main()
