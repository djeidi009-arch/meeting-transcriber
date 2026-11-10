import json
from datetime import datetime

from transcriber import progress


def test_write_is_readable_json_and_clear_removes_it(tmp_path):
    progress.write(tmp_path, progress.ASR, 0.5)
    data = json.loads((tmp_path / "progress.json").read_text())
    assert data["stage"] == "asr" and data["fraction"] == 0.5
    assert datetime.fromisoformat(data["updatedAt"]).tzinfo is not None
    assert not list(tmp_path.glob("*.tmp"))  # запись атомарная, хвостов нет

    progress.write(tmp_path, progress.SUMMARY)
    assert json.loads((tmp_path / "progress.json").read_text())["fraction"] is None

    progress.clear(tmp_path)
    assert not (tmp_path / "progress.json").exists()
    progress.clear(tmp_path)  # повторно — без ошибки


def test_stage_names_match_contract():
    assert (progress.EXTRACT, progress.ASR, progress.DIARIZE, progress.SUMMARY) == ("extract", "asr", "diarize", "summary")
