"""Настройки из ~/.config/meeting-transcriber/config.json."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from pathlib import Path

CONFIG_PATH = Path.home() / ".config" / "meeting-transcriber" / "config.json"
PROJECT_DIR = Path(__file__).resolve().parents[1]


@dataclass
class Config:
    output_dir: Path = Path.home() / "transcripts"
    language: str = "ru"
    claude_path: str = "claude"
    python_path: str = str(PROJECT_DIR / ".venv" / "bin" / "python")
    summary_timeout_sec: int = 300
    extra_bundle_ids: list[str] = field(default_factory=list)
    extra_title_patterns: list[str] = field(default_factory=list)


_KEYS = {
    "outputDir": "output_dir",
    "language": "language",
    "claudePath": "claude_path",
    "pythonPath": "python_path",
    "summaryTimeoutSec": "summary_timeout_sec",
    "extraBundleIDs": "extra_bundle_ids",
    "extraTitlePatterns": "extra_title_patterns",
}


def load(path: Path | None = None) -> Config:
    """Нет файла, битый JSON или нет ключа — значение по умолчанию."""
    cfg = Config()
    try:
        data = json.loads((path or CONFIG_PATH).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return cfg
    if not isinstance(data, dict):
        return cfg
    for key, attr in _KEYS.items():
        value = data.get(key)
        if value is None:
            continue
        if attr == "output_dir" and isinstance(value, str) and value:
            cfg.output_dir = Path(value).expanduser()
        elif attr == "summary_timeout_sec" and isinstance(value, (int, float)) and value > 0:
            cfg.summary_timeout_sec = int(value)
        elif attr.startswith("extra_") and isinstance(value, list):
            setattr(cfg, attr, [str(v) for v in value])
        elif attr in ("claude_path", "python_path") and isinstance(value, str) and value:
            # как expandingTildeInPath в Swift: «~/…» → домашняя папка
            setattr(cfg, attr, os.path.expanduser(value))
        elif attr == "language" and isinstance(value, str) and value:
            cfg.language = value
    return cfg
