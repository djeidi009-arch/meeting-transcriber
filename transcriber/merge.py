"""Склейка реплик: спикеры, эхо, объединение дорожек. Чистые функции."""
from __future__ import annotations

import difflib

from .models import Segment, Turn, Utterance

ME = "Я"
ECHO_WINDOW_SEC = 1.0
GLUE_PAUSE_SEC = 30.0


def _overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def _distance(seg: Segment, turn: Turn) -> float:
    if turn.end < seg.start:
        return seg.start - turn.end
    if turn.start > seg.end:
        return turn.start - seg.end
    return 0.0


def assign_speakers(segments: list[Segment], turns: list[Turn]) -> list[Utterance]:
    """Каждому сегменту — спикер с наибольшим перекрытием (иначе ближайший),
    метки переименованы в «Спикер N» в порядке первого появления."""
    names: dict[str, str] = {}
    result: list[Utterance] = []
    for seg in segments:
        if not turns:
            label = "__single__"
        else:
            best = max(turns, key=lambda t: _overlap(seg.start, seg.end, t.start, t.end))
            if _overlap(seg.start, seg.end, best.start, best.end) <= 0:
                best = min(turns, key=lambda t: _distance(seg, t))
            label = best.speaker
        if label not in names:
            names[label] = f"Спикер {len(names) + 1}"
        result.append(Utterance(seg.start, seg.end, names[label], seg.text))
    return result


def mic_utterances(segments: list[Segment]) -> list[Utterance]:
    return [Utterance(s.start, s.end, ME, s.text) for s in segments]


def _normalize(text: str) -> str:
    return " ".join(text.lower().split())


def drop_echo(mic: list[Utterance], system: list[Utterance], threshold: float = 0.6) -> list[Utterance]:
    """Убирает из mic реплики, которые совпадают по времени (±1 с) и по тексту
    с репликой system: это эхо собеседника, попавшее в микрофон."""
    kept: list[Utterance] = []
    for m in mic:
        mtext = _normalize(m.text)
        is_echo = False
        for s in system:
            close = m.start <= s.end + ECHO_WINDOW_SEC and s.start <= m.end + ECHO_WINDOW_SEC
            if close and difflib.SequenceMatcher(None, mtext, _normalize(s.text)).ratio() >= threshold:
                is_echo = True
                break
        if not is_echo:
            kept.append(m)
    return kept


def combine(mic: list[Utterance], system: list[Utterance]) -> list[Utterance]:
    """Сортировка по времени и склейка подряд идущих реплик одного спикера."""
    result: list[Utterance] = []
    for u in sorted([*mic, *system], key=lambda u: (u.start, u.end)):
        prev = result[-1] if result else None
        if prev and prev.speaker == u.speaker and u.start - prev.end <= GLUE_PAUSE_SEC:
            result[-1] = Utterance(prev.start, max(prev.end, u.end), prev.speaker, f"{prev.text} {u.text}".strip())
        else:
            result.append(u)
    return result
