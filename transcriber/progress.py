"""progress.json — этап обработки для окна приложения. Пишет только Python, Swift читает."""
from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path

EXTRACT, ASR, DIARIZE, SUMMARY = "extract", "asr", "diarize", "summary"

FILE = "progress.json"


def write(meeting_dir: Path, stage: str, fraction: float | None = None) -> None:
    path = Path(meeting_dir) / FILE
    tmp = path.with_name(FILE + ".tmp")
    updated = datetime.now().astimezone().isoformat(timespec="seconds")
    tmp.write_text(json.dumps({"stage": stage, "fraction": fraction, "updatedAt": updated}), encoding="utf-8")
    tmp.replace(path)


def clear(meeting_dir: Path) -> None:
    (Path(meeting_dir) / FILE).unlink(missing_ok=True)
