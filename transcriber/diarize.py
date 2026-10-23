"""Разбивка дорожки звука компьютера по спикерам: pyannote community-1."""
from __future__ import annotations

from pathlib import Path

from .audio import SAMPLE_RATE, read_wav16k
from .models import Turn
from .models_cache import local_snapshot

MODEL = "pyannote/speaker-diarization-community-1"

__all__ = ["Turn", "diarize"]


def diarize(wav: Path) -> list[Turn]:
    import warnings

    import torch

    with warnings.catch_warnings():
        # torchcodec не нужен: звук передаём массивом, а не путём к файлу
        warnings.filterwarnings("ignore", category=UserWarning, module=r"pyannote\.audio\.core\.io")
        from pyannote.audio import Pipeline

    # токен HF huggingface_hub берёт сам из ~/.cache/huggingface/token
    pipeline = Pipeline.from_pretrained(local_snapshot(MODEL))
    if pipeline is None:
        raise RuntimeError(f"не удалось загрузить модель {MODEL}")
    if torch.backends.mps.is_available():
        pipeline.to(torch.device("mps"))

    waveform = torch.from_numpy(read_wav16k(wav)).unsqueeze(0)
    output = pipeline({"waveform": waveform, "sample_rate": SAMPLE_RATE})
    annotation = getattr(output, "speaker_diarization", output)
    return [
        Turn(float(segment.start), float(segment.end), str(label))
        for segment, _, label in annotation.itertracks(yield_label=True)
    ]
