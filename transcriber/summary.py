"""Summary встречи через `claude -p` (Claude Code по подписке, без инструментов)."""
from __future__ import annotations

import os
import signal
import subprocess
import tempfile

PROMPT = """Ниже — транскрипт рабочей встречи на русском. «Я» — владелец записи, «Спикер N» — другие участники.
Сделай краткое summary встречи в Markdown строго из четырёх разделов с заголовками третьего уровня:

### Кратко
2–5 предложений: о чём встреча и к чему пришли.

### Решения
Маркированный список принятых решений. Если решений нет — «Нет».

### Задачи
Маркированный список в формате «**Кто** — что сделать (срок, если назван)». Если задач нет — «Нет».

### Открытые вопросы
Маркированный список нерешённых вопросов. Если их нет — «Нет».

Пиши только по содержанию транскрипта, ничего не выдумывай. Не задавай вопросов, не добавляй вступлений и заключений — выведи только эти четыре раздела.

Транскрипт:
"""


class SummaryError(Exception):
    """Summary не получилось; reason — причина по-русски для meeting.md."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


def build_command(claude_path: str) -> list[str]:
    return [
        claude_path,
        "-p",
        "--output-format",
        "text",
        "--tools",
        "",
        "--strict-mcp-config",
        "--no-session-persistence",
    ]


def summarize(transcript: str, claude_path: str, timeout: int) -> str:
    try:
        proc = subprocess.Popen(
            build_command(claude_path),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=tempfile.gettempdir(),
            start_new_session=True,
        )
    except (FileNotFoundError, PermissionError, OSError) as exc:
        raise SummaryError(f"не найден Claude Code ({claude_path})") from exc

    try:
        out, err = proc.communicate(PROMPT + transcript, timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.communicate()
        raise SummaryError(f"истёк таймаут {timeout} с") from None

    if proc.returncode != 0:
        detail = (err or out or "").strip().splitlines()
        tail = f": {detail[-1][:200]}" if detail else ""
        raise SummaryError(f"Claude Code завершился с кодом {proc.returncode}{tail}")
    if not out.strip():
        raise SummaryError("Claude Code вернул пустой ответ")
    return out.strip()
