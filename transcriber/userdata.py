"""user.json — название встречи и имена спикеров. Пишет только приложение, Python читает."""
from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path


@dataclass(frozen=True)
class UserData:
    title: str | None = None
    speakers: dict[str, str] = field(default_factory=dict)

    def name(self, label: str) -> str:
        return self.speakers.get(label) or label


def load(meeting_dir: Path) -> UserData:
    """Нет файла или он битый — пустые правки: обработка из-за них падать не должна."""
    try:
        data = json.loads((Path(meeting_dir) / "user.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return UserData()
    if not isinstance(data, dict):
        return UserData()
    title = data.get("title")
    speakers = data.get("speakers")
    return UserData(
        title=title.strip() if isinstance(title, str) and title.strip() else None,
        speakers={k: v.strip() for k, v in speakers.items() if isinstance(v, str) and v.strip()}
        if isinstance(speakers, dict)
        else {},
    )
