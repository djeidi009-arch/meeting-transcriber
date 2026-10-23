"""Конвертация дорожек через ffmpeg."""
from __future__ import annotations

import shutil
import subprocess
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 16000
SILENCE_PEAK = 0.003  # пик ниже этого (≈ -50 dBFS) — дорожка считается немой
MIN_DURATION_SEC = 0.3
HEADER_ONLY_BYTES = 4096  # CAF без звука — только заголовок


class AudioError(Exception):
    pass


def ffmpeg_path() -> str:
    for candidate in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"):
        if Path(candidate).exists():
            return candidate
    found = shutil.which("ffmpeg")
    if not found:
        raise AudioError("не найден ffmpeg (brew install ffmpeg)")
    return found


def _run_ffmpeg(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(
        [ffmpeg_path(), "-hide_banner", "-loglevel", "error", "-nostdin", "-y", *args],
        capture_output=True,
        text=True,
    )


def read_wav16k(path: Path) -> np.ndarray:
    """Моно 16 кГц PCM16 → float32 [-1, 1]."""
    with wave.open(str(path), "rb") as w:
        frames = w.readframes(w.getnframes())
    return np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0


def to_wav16k(src: Path, dst: Path) -> bool:
    """False — дорожки нет, она пустая или немая."""
    if not src.exists() or src.stat().st_size == 0:
        return False
    result = _run_ffmpeg(["-i", str(src), "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", str(dst)])
    if result.returncode != 0:
        if src.stat().st_size <= HEADER_ONLY_BYTES:
            return False
        raise AudioError(f"ffmpeg не смог прочитать {src.name}: {result.stderr.strip()[:200]}")
    samples = read_wav16k(dst)
    if samples.size < MIN_DURATION_SEC * SAMPLE_RATE or float(np.abs(samples).max()) < SILENCE_PEAK:
        return False
    return True


def to_m4a(src: Path, dst: Path) -> None:
    tmp = dst.with_name(dst.stem + ".part.m4a")
    result = _run_ffmpeg(["-i", str(src), "-vn", "-c:a", "aac", "-b:a", "64k", str(tmp)])
    if result.returncode != 0:
        tmp.unlink(missing_ok=True)
        raise AudioError(f"ffmpeg не смог сжать {src.name}: {result.stderr.strip()[:200]}")
    tmp.replace(dst)
