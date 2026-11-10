"""Обработка папки встречи: дорожки → текст → спикеры → summary → meeting.md."""
from __future__ import annotations

import json
import re
import tempfile
from dataclasses import asdict
from pathlib import Path
from typing import Callable

from . import audio, merge, progress, render, userdata
from .config import Config
from .models import Segment, Turn, Utterance
from .summary import SummaryError
from .userdata import UserData

TRACKS = ("mic", "system")

AsrFn = Callable[[Path, str], list[Segment]]
DiarizeFn = Callable[[Path], list[Turn]]
SummarizeFn = Callable[[str, str, int], str]


class ProcessingError(Exception):
    """Ошибка обработки; текст — по-русски, одной строкой."""


def _default_asr(wav: Path, language: str) -> list[Segment]:
    from .asr import transcribe

    return transcribe(wav, language)


def _default_diarize(wav: Path) -> list[Turn]:
    from .diarize import diarize

    return diarize(wav)


def _default_summarize(transcript: str, claude_path: str, timeout: int) -> str:
    from .summary import summarize

    return summarize(transcript, claude_path, timeout)


def _check_dir(meeting_dir: Path) -> None:
    if not meeting_dir.is_dir():
        raise ProcessingError(f"Папка встречи не найдена: {meeting_dir}")


def _read_meta(meeting_dir: Path) -> dict:
    try:
        meta = json.loads((meeting_dir / "meta.json").read_text(encoding="utf-8"))
        if isinstance(meta, dict):
            return meta
    except (OSError, ValueError):
        pass
    # без meta.json — имя приложения из имени папки «ГГГГ-ММ-ДД ЧЧ-ММ Приложение»
    match = re.match(r"\d{4}-\d{2}-\d{2} \d{2}-\d{2} (.+?)(?: \(\d+\))?$", meeting_dir.name)
    return {"app": match.group(1) if match else meeting_dir.name, "startedAt": None, "endedAt": None}


def _write_atomic(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    tmp.replace(path)


def _summarize(
    meeting_dir: Path, utterances: list[Utterance], user: UserData, cfg: Config, summarize: SummarizeFn
) -> tuple[str | None, str | None]:
    progress.write(meeting_dir, progress.SUMMARY)
    if not utterances:
        return None, None
    try:
        return summarize(render.transcript_text(utterances, user), cfg.claude_path, cfg.summary_timeout_sec), None
    except SummaryError as exc:
        return None, exc.reason


def _track_source(meeting_dir: Path, track: str) -> Path | None:
    for ext in ("caf", "m4a"):
        candidate = meeting_dir / f"{track}.{ext}"
        if candidate.exists():
            return candidate
    return None


def _import_source(meeting_dir: Path, meta: dict) -> None:
    """Загруженный файл (meta.sourceFile, аудио или видео) → system.m4a: все голоса делит диаризация."""
    source = meta.get("sourceFile")
    if not source or any(_track_source(meeting_dir, t) for t in TRACKS):
        return
    src = Path(source)
    if not src.is_file():
        raise ProcessingError(f"Файл не найден: {src}")
    audio.to_m4a(src, meeting_dir / "system.m4a")


def _process(
    meeting_dir: Path, cfg: Config, asr: AsrFn, diarize: DiarizeFn, summarize: SummarizeFn
) -> str | None:
    if (meeting_dir / ".recording").exists():
        raise ProcessingError("Запись ещё идёт (есть маркер .recording)")
    progress.write(meeting_dir, progress.EXTRACT)
    meta = _read_meta(meeting_dir)
    _import_source(meeting_dir, meta)

    segments: dict[str, list[Segment]] = {track: [] for track in TRACKS}
    turns: list[Turn] = []
    duration = 0.0
    with tempfile.TemporaryDirectory(prefix="transcriber-") as tmp:
        sources = [(track, src) for track in TRACKS if (src := _track_source(meeting_dir, track))]
        for index, (track, src) in enumerate(sources):
            wav = Path(tmp) / f"{track}.wav"
            has_sound = audio.to_wav16k(src, wav)
            duration = max(duration, audio.wav_duration(wav))
            if src.suffix == ".caf" and src.stat().st_size > audio.HEADER_ONLY_BYTES:
                audio.to_m4a(src, meeting_dir / f"{track}.m4a")
            if not has_sound:
                continue
            progress.write(meeting_dir, progress.ASR, index / len(sources))
            segments[track] = asr(wav, cfg.language)
            if track == "system" and segments[track]:
                progress.write(meeting_dir, progress.DIARIZE)
                turns = diarize(wav)

    progress.write(meeting_dir, progress.DIARIZE)  # склейка — тоже этап «Спикеры», даже если диаризации не было
    system_u = merge.assign_speakers(segments["system"], turns)
    mic_u = merge.drop_echo(merge.mic_utterances(segments["mic"]), system_u)
    utterances = merge.combine(mic_u, system_u)

    _write_atomic(
        meeting_dir / "transcript.json",
        json.dumps(
            {"utterances": [asdict(u) for u in utterances], "duration": round(duration, 2)},
            ensure_ascii=False,
            indent=1,
        ),
    )
    user = userdata.load(meeting_dir)
    summary_text, summary_error = _summarize(meeting_dir, utterances, user, cfg, summarize)
    _write_atomic(
        meeting_dir / "meeting.md",
        render.render_markdown(meta, summary_text, summary_error, utterances, audio_duration=duration, user=user),
    )

    (meeting_dir / "error.txt").unlink(missing_ok=True)
    for track in TRACKS:
        caf = meeting_dir / f"{track}.caf"
        if caf.exists() and ((meeting_dir / f"{track}.m4a").exists() or caf.stat().st_size <= audio.HEADER_ONLY_BYTES):
            caf.unlink()
    return summary_error


def _record_error(meeting_dir: Path, exc: Exception) -> None:
    try:
        (meeting_dir / "error.txt").write_text(f"{error_message(exc)}\n", encoding="utf-8")
    except OSError:
        pass


def error_message(exc: Exception) -> str:
    if isinstance(exc, (ProcessingError, audio.AudioError)):
        text = str(exc)
    else:
        text = f"Ошибка обработки: {type(exc).__name__}: {exc}"
    return " ".join(text.split())


def process(
    meeting_dir: Path,
    cfg: Config,
    asr: AsrFn | None = None,
    diarize: DiarizeFn | None = None,
    summarize: SummarizeFn | None = None,
) -> str | None:
    """Обработать папку встречи. Уже обработанная (есть meeting.md) — ничего не делает.

    Возвращает причину сбоя summary (транскрипт при этом готов) или None.
    """
    meeting_dir = Path(meeting_dir)
    _check_dir(meeting_dir)
    if (meeting_dir / "meeting.md").exists():
        return None
    try:
        return _process(meeting_dir, cfg, asr or _default_asr, diarize or _default_diarize, summarize or _default_summarize)
    except Exception as exc:
        _record_error(meeting_dir, exc)
        raise
    finally:
        progress.clear(meeting_dir)


def resummarize(meeting_dir: Path, cfg: Config, summarize: SummarizeFn | None = None) -> str | None:
    """Заново сделать summary по transcript.json и перезаписать meeting.md.

    Как и process, возвращает причину сбоя summary или None.
    """
    meeting_dir = Path(meeting_dir)
    _check_dir(meeting_dir)
    try:
        data = json.loads((meeting_dir / "transcript.json").read_text(encoding="utf-8"))
        utterances = [Utterance(**u) for u in data["utterances"]]
        duration = data.get("duration")
        duration = float(duration) if isinstance(duration, (int, float)) else None
    except (OSError, ValueError, KeyError, TypeError) as exc:
        raise ProcessingError("Нет транскрипта (transcript.json): сначала нужна обработка встречи") from exc

    user = userdata.load(meeting_dir)
    try:
        summary_text, summary_error = _summarize(meeting_dir, utterances, user, cfg, summarize or _default_summarize)
        _write_atomic(
            meeting_dir / "meeting.md",
            render.render_markdown(
                _read_meta(meeting_dir), summary_text, summary_error, utterances, audio_duration=duration, user=user
            ),
        )
    finally:
        progress.clear(meeting_dir)
    return summary_error
