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


def test_duration_from_meta_wins_over_audio():
    md = render_markdown(META, None, None, [Utterance(0.0, 1.0, "Я", "Привет")], audio_duration=49.7)
    assert "Длительность: 1 ч 5 мин" in md


def test_duration_without_end_time_uses_longest_track():
    md = render_markdown({**META, "endedAt": None}, None, None, [Utterance(0.0, 40.0, "Я", "Привет")], audio_duration=49.7)
    assert "Длительность: 50 с" in md


def test_user_title_and_speaker_names_are_applied():
    from transcriber.render import transcript_text
    from transcriber.userdata import UserData

    user = UserData(title="Планёрка по релизу", speakers={"Спикер 1": "Аня"})
    utterances = [Utterance(5.0, 9.0, "Спикер 1", "Начнём."), Utterance(10.0, 11.0, "Я", "Да.")]
    lines = render_markdown(META, None, None, utterances, user=user).splitlines()
    assert lines[0] == "# Планёрка по релизу — 23.10.2026 15:30"
    assert "**[00:00:05] Аня:** Начнём." in lines
    assert "**[00:00:10] Я:** Да." in lines
    assert transcript_text(utterances, user) == "[00:00:05] Аня: Начнём.\n[00:00:10] Я: Да."
