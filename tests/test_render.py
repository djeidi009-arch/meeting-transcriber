from transcriber.models import Utterance
from transcriber.render import render_markdown

META = {
    "app": "Zoom",
    "bundleId": "us.zoom.xos",
    "startedAt": "2026-10-23T15:30:00+03:00",
    "endedAt": "2026-10-23T16:35:30+03:00",
    "manual": False,
}


def test_render_full_meeting():
    utterances = [
        Utterance(5.0, 9.0, "Спикер 1", "Начнём."),
        Utterance(3725.4, 3730.0, "Я", "Всем спасибо."),
    ]
    md = render_markdown(META, "### Кратко\nОбсудили бюджет.", None, utterances)
    lines = md.splitlines()
    assert lines[0] == "# Zoom — 23.10.2026 15:30"
    assert "Длительность: 1 ч 5 мин" in md
    assert "## Summary" in md
    assert "Обсудили бюджет." in md
    assert md.index("## Summary") < md.index("## Транскрипт")
    assert "**[00:00:05] Спикер 1:** Начнём." in lines
    assert "**[01:02:05] Я:** Всем спасибо." in lines


def test_render_summary_error_keeps_transcript():
    utterances = [Utterance(0.0, 1.0, "Я", "Привет")]
    md = render_markdown(META, None, "истёк таймаут", utterances)
    assert "Summary не удалось сделать: истёк таймаут. Меню → Повторить summary" in md
    assert "**[00:00:00] Я:** Привет" in md


def test_render_empty_speech():
    md = render_markdown({**META, "endedAt": None}, None, None, [])
    assert "Речь не распознана" in md
    assert "## Транскрипт" in md
