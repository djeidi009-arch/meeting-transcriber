import json
import stat
import sys
from pathlib import Path

import pytest

from transcriber.summary import SummaryError, summarize


def make_fake_claude(tmp_path: Path, body: str) -> Path:
    """Фейковый `claude`: сохраняет argv и stdin рядом и выполняет body."""
    script = tmp_path / "claude"
    script.write_text(
        "#!/bin/sh\n"
        f"'{sys.executable}' -c \"import json,sys; json.dump(sys.argv[1:], open('{tmp_path}/argv.json','w'))\" \"$@\"\n"
        f"cat > '{tmp_path}/stdin.txt'\n"
        f"{body}\n"
    )
    script.chmod(script.stat().st_mode | stat.S_IEXEC)
    return script


def test_summarize_passes_transcript_via_stdin_without_tools(tmp_path):
    fake = make_fake_claude(tmp_path, "printf '### Кратко\\nВсё хорошо\\n'")
    result = summarize("**[00:00:01] Я:** Привет", str(fake), timeout=10)
    assert result.strip() == "### Кратко\nВсё хорошо"
    argv = json.loads((tmp_path / "argv.json").read_text())
    assert argv[:3] == ["-p", "--output-format", "text"]
    i = argv.index("--tools")
    assert argv[i + 1] == ""
    stdin = (tmp_path / "stdin.txt").read_text()
    assert "**[00:00:01] Я:** Привет" in stdin


@pytest.mark.parametrize(
    "body",
    [
        "echo 'boom' >&2; exit 3",  # ненулевой код
        "exit 0",  # пустой вывод
        "printf '   \\n'",  # только пробелы
    ],
)
def test_summarize_failures_raise(tmp_path, body):
    fake = make_fake_claude(tmp_path, body)
    with pytest.raises(SummaryError) as err:
        summarize("текст", str(fake), timeout=10)
    assert err.value.reason


def test_summarize_timeout_raises(tmp_path):
    fake = make_fake_claude(tmp_path, "sleep 5; echo late")
    with pytest.raises(SummaryError) as err:
        summarize("текст", str(fake), timeout=1)
    assert "таймаут" in err.value.reason


def test_summarize_missing_binary_raises(tmp_path):
    with pytest.raises(SummaryError):
        summarize("текст", str(tmp_path / "nope" / "claude"), timeout=5)
