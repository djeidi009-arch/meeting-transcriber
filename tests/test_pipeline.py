import json
import subprocess
import sys
from pathlib import Path

import pytest

from transcriber.audio import ffmpeg_path
from transcriber.config import Config
from transcriber.models import Segment, Turn
from transcriber.pipeline import ProcessingError, process, resummarize
from transcriber.summary import SummaryError

META = {
    "app": "Zoom",
    "bundleId": "us.zoom.xos",
    "startedAt": "2026-10-23T15:30:00+03:00",
    "endedAt": "2026-10-23T15:31:00+03:00",
    "manual": False,
}


def make_caf(path: Path, source: str) -> None:
    subprocess.run(
        [ffmpeg_path(), "-loglevel", "error", "-y", "-f", "lavfi", "-i", source, "-t", "2", "-c:a", "pcm_f32le", str(path)],
        check=True,
    )


TONE = "sine=frequency=440:sample_rate=48000"
SILENCE = "anullsrc=r=48000:cl=mono"


def meeting(tmp_path: Path, mic: str | None = TONE, system: str | None = TONE) -> Path:
    d = tmp_path / "2026-10-23 15-30 Zoom"
    d.mkdir()
    (d / "meta.json").write_text(json.dumps(META))
    if mic:
        make_caf(d / "mic.caf", mic)
    if system:
        make_caf(d / "system.caf", system)
    return d


class Fakes:
    def __init__(self, summary="### Кратко\nОбсудили план."):
        self.asr_calls: list[str] = []
        self.diarize_calls = 0
        self.summary_inputs: list[str] = []
        self.summary = summary

    def asr(self, wav: Path, language: str):
        assert language == "ru"
        name = wav.name
        self.asr_calls.append(name)
        if name.startswith("mic"):
            return [
                Segment(3.0, 4.0, "Я согласен"),
                Segment(0.2, 1.8, "давайте начнём встречу"),  # эхо собеседника
            ]
        return [Segment(0.0, 1.5, "Давайте начнём встречу"), Segment(5.0, 6.0, "Отлично")]

    def diarize(self, wav: Path):
        self.diarize_calls += 1
        return [Turn(0.0, 1.6, "SPEAKER_03"), Turn(4.8, 6.0, "SPEAKER_00")]

    def summarize(self, transcript: str, claude_path: str, timeout: int):
        self.summary_inputs.append(transcript)
        if isinstance(self.summary, Exception):
            raise self.summary
        return self.summary


def run(d: Path, fakes: Fakes):
    process(d, Config(), asr=fakes.asr, diarize=fakes.diarize, summarize=fakes.summarize)


def test_process_builds_meeting_files_and_removes_caf(tmp_path):
    d = meeting(tmp_path)
    (d / "error.txt").write_text("старая ошибка")
    fakes = Fakes()
    run(d, fakes)

    md = (d / "meeting.md").read_text()
    assert md.startswith("# Zoom — 23.10.2026 15:30")
    assert "Обсудили план." in md
    assert "**[00:00:00] Спикер 1:** Давайте начнём встречу" in md
    assert "**[00:00:03] Я:** Я согласен" in md
    assert "**[00:00:05] Спикер 2:** Отлично" in md
    assert "давайте начнём встречу" not in md  # эхо убрано

    data = json.loads((d / "transcript.json").read_text())
    assert [u["speaker"] for u in data["utterances"]] == ["Спикер 1", "Я", "Спикер 2"]
    assert "Я согласен" in fakes.summary_inputs[0]

    assert (d / "mic.m4a").stat().st_size > 0
    assert (d / "system.m4a").stat().st_size > 0
    assert not (d / "mic.caf").exists() and not (d / "system.caf").exists()
    assert not (d / "error.txt").exists()


def test_process_twice_is_noop(tmp_path):
    d = meeting(tmp_path)
    run(d, Fakes())
    before = (d / "meeting.md").read_text()
    again = Fakes()
    run(d, again)
    assert again.asr_calls == [] and again.summary_inputs == []
    assert (d / "meeting.md").read_text() == before


def test_process_without_mic_track(tmp_path):
    d = meeting(tmp_path, mic=None)
    fakes = Fakes()
    run(d, fakes)
    assert fakes.asr_calls == ["system.wav"]
    assert not (d / "mic.m4a").exists()
    assert "Спикер 1" in (d / "meeting.md").read_text()


def test_process_silent_system_track_skips_asr_and_diarize(tmp_path):
    d = meeting(tmp_path, system=SILENCE)
    fakes = Fakes()
    run(d, fakes)
    assert fakes.asr_calls == ["mic.wav"]
    assert fakes.diarize_calls == 0
    md = (d / "meeting.md").read_text()
    assert "**[00:00:00] Я:** давайте начнём встречу" in md  # без system эха нет


def test_process_no_speech_at_all(tmp_path):
    d = meeting(tmp_path, mic=SILENCE, system=None)
    fakes = Fakes()
    run(d, fakes)
    assert "Речь не распознана" in (d / "meeting.md").read_text()
    assert fakes.summary_inputs == []


def test_process_summary_failure_still_writes_transcript(tmp_path):
    d = meeting(tmp_path)
    run(d, Fakes(summary=SummaryError("истёк таймаут 300 с")))
    md = (d / "meeting.md").read_text()
    assert "Summary не удалось сделать: истёк таймаут 300 с. Меню → Повторить summary" in md
    assert "Я согласен" in md


def test_process_error_writes_error_txt_and_keeps_caf(tmp_path):
    d = meeting(tmp_path)
    fakes = Fakes()

    def broken_asr(wav, language):
        raise RuntimeError("модель не загрузилась")

    with pytest.raises(Exception):
        process(d, Config(), asr=broken_asr, diarize=fakes.diarize, summarize=fakes.summarize)
    assert "модель не загрузилась" in (d / "error.txt").read_text()
    assert not (d / "meeting.md").exists()
    assert (d / "mic.caf").exists() and (d / "system.caf").exists()


def test_process_retry_after_error_succeeds(tmp_path):
    d = meeting(tmp_path)

    def broken_asr(wav, language):
        raise RuntimeError("сбой")

    fakes = Fakes()
    with pytest.raises(Exception):
        process(d, Config(), asr=broken_asr, diarize=fakes.diarize, summarize=fakes.summarize)
    run(d, fakes)
    assert (d / "meeting.md").exists() and not (d / "error.txt").exists()


def test_resummarize_rewrites_summary_without_asr(tmp_path):
    d = meeting(tmp_path)
    run(d, Fakes(summary=SummaryError("сбой")))
    second = Fakes(summary="### Кратко\nНовое summary.")
    resummarize(d, Config(), summarize=second.summarize)
    md = (d / "meeting.md").read_text()
    assert "Новое summary." in md
    assert "Summary не удалось" not in md
    assert "**[00:00:03] Я:** Я согласен" in md
    assert second.asr_calls == [] and len(second.summary_inputs) == 1


def test_resummarize_without_transcript_fails(tmp_path):
    d = meeting(tmp_path)
    with pytest.raises(ProcessingError):
        resummarize(d, Config(), summarize=Fakes().summarize)


def test_cli_exit_code_and_russian_error(tmp_path):
    result = subprocess.run(
        [sys.executable, "-m", "transcriber", "process", str(tmp_path / "нет такой папки")],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 1
    assert "не найдена" in result.stderr
    assert len(result.stderr.strip().splitlines()) == 1


def test_cli_process_on_done_meeting_is_noop(tmp_path):
    d = tmp_path / "m"
    d.mkdir()
    (d / "meeting.md").write_text("готово")
    result = subprocess.run([sys.executable, "-m", "transcriber", "process", str(d)], capture_output=True, text=True)
    assert result.returncode == 0
    assert (d / "meeting.md").read_text() == "готово"


def test_process_reports_summary_failure_to_caller(tmp_path):
    d = meeting(tmp_path)
    fakes = Fakes(summary=SummaryError("истёк таймаут 300 с"))
    result = process(d, Config(), asr=fakes.asr, diarize=fakes.diarize, summarize=fakes.summarize)
    assert result == "истёк таймаут 300 с"
    assert (d / "meeting.md").exists() and not (d / "error.txt").exists()


def test_process_returns_none_when_summary_ok(tmp_path):
    d = meeting(tmp_path)
    fakes = Fakes()
    assert process(d, Config(), asr=fakes.asr, diarize=fakes.diarize, summarize=fakes.summarize) is None


def test_cli_summary_failure_exit_code_2(tmp_path, monkeypatch, capsys):
    from transcriber import __main__ as cli
    from transcriber import pipeline

    d = tmp_path / "m"
    d.mkdir()
    monkeypatch.setattr(pipeline, "process", lambda meeting_dir, cfg: "claude не ответил")
    code = cli.main(["process", str(d)])
    assert code == cli.EXIT_SUMMARY_FAILED == 2
    err = capsys.readouterr().err.strip().splitlines()
    assert len(err) == 1 and "claude не ответил" in err[0]
