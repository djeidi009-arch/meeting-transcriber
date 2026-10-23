from transcriber.merge import assign_speakers, combine, drop_echo, mic_utterances
from transcriber.models import Segment, Turn, Utterance


def test_assign_speakers_picks_largest_overlap_and_numbers_by_first_appearance():
    segments = [
        Segment(0.0, 4.0, "Привет"),
        Segment(5.0, 9.0, "Здравствуйте"),
        Segment(10.0, 12.0, "Как дела"),
    ]
    turns = [
        Turn(0.0, 1.0, "SPEAKER_01"),
        Turn(1.0, 4.5, "SPEAKER_00"),  # перекрытие 3 с против 1 с
        Turn(4.5, 9.0, "SPEAKER_01"),
        Turn(9.5, 12.0, "SPEAKER_00"),
    ]
    result = assign_speakers(segments, turns)
    assert [u.speaker for u in result] == ["Спикер 1", "Спикер 2", "Спикер 1"]
    assert [u.text for u in result] == ["Привет", "Здравствуйте", "Как дела"]
    assert (result[1].start, result[1].end) == (5.0, 9.0)


def test_assign_speakers_without_overlap_takes_nearest_turn():
    segments = [Segment(0.0, 1.0, "раз"), Segment(20.0, 21.0, "два")]
    turns = [Turn(2.0, 3.0, "A"), Turn(15.0, 19.0, "B")]
    result = assign_speakers(segments, turns)
    assert [u.speaker for u in result] == ["Спикер 1", "Спикер 2"]


def test_assign_speakers_without_turns_is_single_speaker():
    segments = [Segment(0.0, 1.0, "раз"), Segment(2.0, 3.0, "два")]
    assert [u.speaker for u in assign_speakers(segments, [])] == ["Спикер 1", "Спикер 1"]


def test_mic_utterances_are_me():
    result = mic_utterances([Segment(1.0, 2.0, "это я")])
    assert result == [Utterance(1.0, 2.0, "Я", "это я")]


def test_drop_echo_removes_similar_overlapping_mic_lines_only():
    system = [Utterance(10.0, 14.0, "Спикер 1", "Давайте обсудим бюджет на следующий квартал")]
    mic = [
        Utterance(10.5, 14.2, "Я", "давайте обсудим бюджет на следующий квартал"),  # эхо
        Utterance(10.0, 14.0, "Я", "Я не согласен совсем"),  # совпадает по времени, другой текст
        Utterance(40.0, 44.0, "Я", "Давайте обсудим бюджет на следующий квартал"),  # тот же текст, другое время
        Utterance(14.8, 16.0, "Я", "Давайте обсудим бюджет на следующий квартал"),  # в пределах ±1 с
    ]
    kept = drop_echo(mic, system)
    assert [u.start for u in kept] == [10.0, 40.0]


def test_drop_echo_threshold_is_configurable():
    system = [Utterance(0.0, 2.0, "Спикер 1", "abcdefghij")]
    mic = [Utterance(0.0, 2.0, "Я", "abcdeXXXXX")]  # ratio 0.5
    assert drop_echo(mic, system) == mic
    assert drop_echo(mic, system, threshold=0.5) == []


def test_combine_sorts_and_glues_consecutive_same_speaker():
    mic = [Utterance(5.0, 6.0, "Я", "Да."), Utterance(7.0, 8.0, "Я", "Согласен.")]
    system = [
        Utterance(0.0, 2.0, "Спикер 1", "Начнём."),
        Utterance(2.5, 4.0, "Спикер 1", "Повестка такая."),
        Utterance(9.0, 10.0, "Спикер 1", "Хорошо."),
        Utterance(50.0, 51.0, "Спикер 1", "Ещё."),  # пауза 40 с — не склеивать
    ]
    result = combine(mic, system)
    assert result == [
        Utterance(0.0, 4.0, "Спикер 1", "Начнём. Повестка такая."),
        Utterance(5.0, 8.0, "Я", "Да. Согласен."),
        Utterance(9.0, 10.0, "Спикер 1", "Хорошо."),
        Utterance(50.0, 51.0, "Спикер 1", "Ещё."),
    ]
