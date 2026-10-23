import json
from pathlib import Path

from transcriber.config import load


def test_load_missing_file_gives_defaults(tmp_path):
    cfg = load(tmp_path / "nope.json")
    assert cfg.output_dir == Path.home() / "transcripts"
    assert cfg.language == "ru"
    assert cfg.claude_path == "claude"
    assert cfg.summary_timeout_sec == 300
    assert cfg.extra_bundle_ids == [] and cfg.extra_title_patterns == []


def test_load_reads_keys_and_keeps_defaults_for_missing(tmp_path):
    path = tmp_path / "config.json"
    path.write_text(json.dumps({
        "outputDir": "~/meetings",
        "language": "en",
        "claudePath": "/usr/local/bin/claude",
        "summaryTimeoutSec": 60,
        "extraBundleIDs": ["com.example.call"],
    }))
    cfg = load(path)
    assert cfg.output_dir == Path.home() / "meetings"
    assert cfg.language == "en"
    assert cfg.claude_path == "/usr/local/bin/claude"
    assert cfg.summary_timeout_sec == 60
    assert cfg.extra_bundle_ids == ["com.example.call"]
    assert cfg.extra_title_patterns == []


def test_load_broken_json_gives_defaults(tmp_path):
    path = tmp_path / "config.json"
    path.write_text("{oops")
    assert load(path).language == "ru"


def test_load_expands_tilde_in_all_paths(tmp_path):
    path = tmp_path / "config.json"
    path.write_text(json.dumps({
        "outputDir": "~/meetings",
        "claudePath": "~/.local/bin/claude",
        "pythonPath": "~/proj/.venv/bin/python",
    }))
    cfg = load(path)
    assert cfg.output_dir == Path.home() / "meetings"
    assert cfg.claude_path == str(Path.home() / ".local/bin/claude")
    assert cfg.python_path == str(Path.home() / "proj/.venv/bin/python")
