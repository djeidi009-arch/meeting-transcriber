"""Модели Hugging Face: сначала локальный кеш, сеть — только для первой загрузки."""
from __future__ import annotations

from pathlib import Path


def local_snapshot(repo_id: str) -> Path:
    from huggingface_hub import snapshot_download

    try:
        # без сети: проверка обновлений на huggingface.co может висеть минутами
        return Path(snapshot_download(repo_id, local_files_only=True))
    except Exception:
        return Path(snapshot_download(repo_id))
