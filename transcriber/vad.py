"""Поиск участков речи по энергии (без моделей).

Whisper на длинной тишине выдумывает текст («Продолжение следует...») и сбивает
таймкоды на десятки секунд. Поэтому расшифровываем только участки со звуком,
каждый отдельно, а таймкоды сдвигаем на начало участка.
"""
from __future__ import annotations

import numpy as np

FRAME_SEC = 0.03
FLOOR_DB = -50.0  # абсолютный порог тишины (≈ пик 0.003 у audio.SILENCE_PEAK)
ABOVE_NOISE_DB = 12.0  # речь — на столько громче фона дорожки
PEAK_RANGE_DB = 20.0  # но порог не выше «пик минус столько» — иначе тихую речь примем за фон
MERGE_GAP_SEC = 1.0  # паузы короче — внутри одной фразы
MIN_REGION_SEC = 0.2
PAD_SEC = 0.3
MAX_REGION_SEC = 28.0  # окно Whisper — 30 с
MIN_CUT_SEC = 15.0  # длинную речь режем в самом тихом месте после этой отметки


def _frame_db(samples: np.ndarray, frame: int) -> np.ndarray:
    count = len(samples) // frame
    if count == 0:
        return np.zeros(0)
    frames = samples[: count * frame].reshape(count, frame).astype(np.float64)
    rms = np.sqrt(np.mean(frames**2, axis=1))
    return 20 * np.log10(np.maximum(rms, 1e-10))


def _split_long(start: int, end: int, db: np.ndarray, max_frames: int, min_cut: int) -> list[tuple[int, int]]:
    parts: list[tuple[int, int]] = []
    while end - start > max_frames:
        window = db[start + min_cut : start + max_frames]
        cut = start + min_cut + int(np.argmin(window))
        parts.append((start, cut))
        start = cut
    parts.append((start, end))
    return parts


def speech_regions(samples: np.ndarray, sample_rate: int) -> list[tuple[float, float]]:
    """Участки речи (начало, конец) в секундах, по возрастанию, без перекрытий, каждый ≤ MAX_REGION_SEC."""
    frame = max(1, int(FRAME_SEC * sample_rate))
    db = _frame_db(np.asarray(samples), frame)
    if db.size == 0:
        return []
    noise = float(np.percentile(db, 10))
    peak = float(db.max())
    threshold = max(FLOOR_DB, min(noise + ABOVE_NOISE_DB, peak - PEAK_RANGE_DB))
    if peak < threshold:
        return []

    voiced = db >= threshold
    # непрерывные участки над порогом
    edges = np.diff(np.concatenate([[0], voiced.astype(np.int8), [0]]))
    starts = np.flatnonzero(edges == 1)
    ends = np.flatnonzero(edges == -1)

    gap = int(round(MERGE_GAP_SEC / FRAME_SEC))
    merged: list[list[int]] = []
    for s, e in zip(starts, ends):
        if merged and s - merged[-1][1] <= gap:
            merged[-1][1] = int(e)
        else:
            merged.append([int(s), int(e)])

    pad = int(round(PAD_SEC / FRAME_SEC))
    min_len = int(round(MIN_REGION_SEC / FRAME_SEC))
    padded: list[tuple[int, int]] = []
    for s, e in merged:
        if e - s < min_len:
            continue
        s, e = max(0, s - pad), min(len(db), e + pad)
        if padded and s <= padded[-1][1]:
            s = padded[-1][1]
            if e <= s:
                continue
        padded.append((s, e))

    max_frames = int(MAX_REGION_SEC / FRAME_SEC)
    min_cut = int(MIN_CUT_SEC / FRAME_SEC)
    regions: list[tuple[float, float]] = []
    for s, e in padded:
        for a, b in _split_long(s, e, db, max_frames, min_cut):
            regions.append((a * frame / sample_rate, min(b * frame, len(samples)) / sample_rate))
    return regions
