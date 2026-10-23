from transcriber.asr import is_hallucination


def test_known_silence_hallucinations_are_filtered():
    assert is_hallucination("Продолжение следует...")
    assert is_hallucination("Субтитры сделал DimaTorzok")
    assert is_hallucination("  ...  ")


def test_normal_speech_is_kept():
    assert not is_hallucination("Тексты могу взять на себя, пришлю черновик в среду.")
    assert not is_hallucination("Продолжим обсуждение бюджета")


import numpy as np

from transcriber.asr import transcribe_samples

SR = 16000


def _speech(sec: float) -> np.ndarray:
    t = np.arange(int(sec * SR)) / SR
    return (0.3 * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def _quiet(sec: float) -> np.ndarray:
    return np.zeros(int(sec * SR), dtype=np.float32)


def test_timestamps_are_shifted_to_speech_start():
    samples = np.concatenate([_quiet(5), _speech(3), _quiet(30), _speech(2), _quiet(2)])
    texts = iter(["Добрый день, начнём.", "Хорошо, расходимся."])

    def decode(chunk):
        # Whisper видит только участок речи и ставит таймкоды от его начала
        return [{"start": 0.0, "end": len(chunk) / SR, "text": next(texts)}]

    segments = transcribe_samples(samples, "ru", decode)
    assert [s.text for s in segments] == ["Добрый день, начнём.", "Хорошо, расходимся."]
    assert abs(segments[0].start - 5.0) <= 1.0
    assert abs(segments[1].start - 38.0) <= 1.0


def test_hallucination_in_one_region_does_not_drop_other_speech():
    samples = np.concatenate([_speech(3), _quiet(25), _speech(3), _quiet(5)])
    outputs = iter([
        [{"start": 0.0, "end": 3.0, "text": "Продолжение следует..."}],
        [{"start": 0.0, "end": 3.0, "text": "Фиксируем решение"}],
    ])

    segments = transcribe_samples(samples, "ru", lambda chunk: next(outputs))
    assert [s.text for s in segments] == ["Фиксируем решение"]
    assert abs(segments[0].start - 28.0) <= 1.0


def test_silent_segments_by_whisper_score_are_dropped():
    samples = np.concatenate([_speech(3)])
    out = [
        {"start": 0.0, "end": 1.0, "text": "Угу", "no_speech_prob": 0.9, "avg_logprob": -1.5},
        {"start": 1.0, "end": 3.0, "text": "Настоящая фраза", "no_speech_prob": 0.1, "avg_logprob": -0.3},
    ]
    segments = transcribe_samples(samples, "ru", lambda chunk: out)
    assert [s.text for s in segments] == ["Настоящая фраза"]
