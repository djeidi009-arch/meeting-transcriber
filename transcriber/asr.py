"""Расшифровка mlx-whisper (large-v3-turbo, локально на Apple Silicon)."""
from __future__ import annotations

from pathlib import Path
from typing import Callable

import numpy as np

from .audio import SAMPLE_RATE, read_wav16k
from .models import Segment
from .models_cache import local_snapshot
from .vad import speech_regions

MODEL_REPO = "mlx-community/whisper-large-v3-turbo"

__all__ = ["Segment", "transcribe", "transcribe_samples"]


# Фразы, которые Whisper выдумывает на тишине (выучены на субтитрах видео)
HALLUCINATIONS = (
    "продолжение следует",
    "субтитры",
    "редактор субтитров",
    "корректор",
    "спасибо за просмотр",
    "подписывайтесь на канал",
    "dimatorzok",
)


def is_hallucination(text: str) -> bool:
    norm = "".join(ch for ch in text.lower() if ch.isalnum() or ch == " ").strip()
    return not norm or any(norm.startswith(phrase) for phrase in HALLUCINATIONS)


Decoder = Callable[[np.ndarray], list[dict]]


def _keep(seg: dict, text: str) -> bool:
    if is_hallucination(text):
        return False
    # тот же критерий тишины, что у Whisper: отсекает галлюцинации на паузах
    return not (seg.get("no_speech_prob", 0.0) > 0.6 and seg.get("avg_logprob", 0.0) < -1.0)


def transcribe_samples(samples: np.ndarray, language: str, decode: Decoder) -> list[Segment]:
    """Расшифровать каждый участок речи отдельно; таймкоды — от начала дорожки.

    `decode(chunk)` возвращает сегменты Whisper (start/end от начала chunk, text, …).
    """
    segments: list[Segment] = []
    for region_start, region_end in speech_regions(samples, SAMPLE_RATE):
        chunk = samples[int(region_start * SAMPLE_RATE) : int(region_end * SAMPLE_RATE)]
        for seg in decode(chunk):
            text = str(seg.get("text", "")).strip()
            if not _keep(seg, text):
                continue
            start = min(region_start + float(seg["start"]), region_end)
            end = min(max(region_start + float(seg["end"]), start), region_end)
            segments.append(Segment(start, end, text))
    return segments


def transcribe(wav: Path, language: str) -> list[Segment]:
    import mlx_whisper  # тяжёлый импорт — только при настоящей расшифровке

    model = str(local_snapshot(MODEL_REPO))

    def decode(chunk: np.ndarray) -> list[dict]:
        result = mlx_whisper.transcribe(
            chunk,  # массив, а не путь: mlx-whisper не будет искать ffmpeg в PATH
            path_or_hf_repo=model,
            language=language,
            condition_on_previous_text=False,
            verbose=None,
        )
        return list(result.get("segments", []))

    return transcribe_samples(read_wav16k(wav), language, decode)
