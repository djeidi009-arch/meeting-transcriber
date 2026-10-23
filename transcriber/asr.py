"""Расшифровка mlx-whisper (large-v3-turbo, локально на Apple Silicon)."""
from __future__ import annotations

from pathlib import Path

from .audio import read_wav16k
from .models import Segment
from .models_cache import local_snapshot

MODEL_REPO = "mlx-community/whisper-large-v3-turbo"

__all__ = ["Segment", "transcribe"]


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


def transcribe(wav: Path, language: str) -> list[Segment]:
    import mlx_whisper  # тяжёлый импорт — только при настоящей расшифровке

    result = mlx_whisper.transcribe(
        read_wav16k(wav),  # массив, а не путь: mlx-whisper не будет искать ffmpeg в PATH
        path_or_hf_repo=str(local_snapshot(MODEL_REPO)),
        language=language,
        condition_on_previous_text=False,
        verbose=None,
    )
    segments: list[Segment] = []
    for seg in result.get("segments", []):
        text = str(seg.get("text", "")).strip()
        if is_hallucination(text):
            continue
        # тот же критерий тишины, что у Whisper: отсекает галлюцинации на паузах
        if seg.get("no_speech_prob", 0.0) > 0.6 and seg.get("avg_logprob", 0.0) < -1.0:
            continue
        segments.append(Segment(float(seg["start"]), float(seg["end"]), text))
    return segments
