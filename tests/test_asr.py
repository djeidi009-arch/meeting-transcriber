from transcriber.asr import is_hallucination


def test_known_silence_hallucinations_are_filtered():
    assert is_hallucination("Продолжение следует...")
    assert is_hallucination("Субтитры сделал DimaTorzok")
    assert is_hallucination("  ...  ")


def test_normal_speech_is_kept():
    assert not is_hallucination("Тексты могу взять на себя, пришлю черновик в среду.")
    assert not is_hallucination("Продолжим обсуждение бюджета")
