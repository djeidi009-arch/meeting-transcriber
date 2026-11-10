"""Сборка meeting.md."""
from __future__ import annotations

from datetime import datetime

from .models import Utterance
from .userdata import UserData


def _parse_time(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _timestamp(seconds: float) -> str:
    total = int(max(0.0, seconds))
    return f"{total // 3600:02d}:{total % 3600 // 60:02d}:{total % 60:02d}"


def _duration(seconds: float) -> str:
    total = int(round(seconds))
    hours, minutes = total // 3600, total % 3600 // 60
    if hours:
        return f"{hours} ч {minutes} мин"
    if minutes:
        return f"{minutes} мин"
    return f"{total} с"


def transcript_text(utterances: list[Utterance], user: UserData = UserData()) -> str:
    """Транскрипт строками `[чч:мм:сс] Спикер: текст` — вход для summary."""
    return "\n".join(f"[{_timestamp(u.start)}] {user.name(u.speaker)}: {u.text}" for u in utterances)


def render_markdown(
    meta: dict,
    summary: str | None,
    summary_error: str | None,
    utterances: list[Utterance],
    audio_duration: float | None = None,
    user: UserData = UserData(),
) -> str:
    """audio_duration — длина самой длинной дорожки; нужна, когда в meta.json нет времени конца.

    user — правки из user.json: название вместо meta.app, имена вместо меток спикеров.
    """
    app = user.title or meta.get("app") or "Встреча"
    started = _parse_time(meta.get("startedAt"))
    ended = _parse_time(meta.get("endedAt"))

    title = f"# {app} — {started.strftime('%d.%m.%Y %H:%M')}" if started else f"# {app}"
    lines = [title, ""]

    if started and ended:
        seconds = (ended - started).total_seconds()
    elif audio_duration is not None:
        seconds = audio_duration
    else:
        seconds = max((u.end for u in utterances), default=0.0)
    lines += [f"Длительность: {_duration(seconds)}", ""]

    lines += ["## Summary", ""]
    if summary_error:
        lines.append(f"Summary не удалось сделать: {summary_error}. Меню → Повторить summary")
    elif summary and summary.strip():
        lines.append(summary.strip())
    else:
        lines.append("Summary нет: в записи нечего обобщать.")
    lines.append("")

    lines += ["## Транскрипт", ""]
    if not utterances:
        lines.append("Речь не распознана")
    else:
        for u in utterances:
            lines.append(f"**[{_timestamp(u.start)}] {user.name(u.speaker)}:** {u.text}")
            lines.append("")
    return "\n".join(lines).rstrip() + "\n"
