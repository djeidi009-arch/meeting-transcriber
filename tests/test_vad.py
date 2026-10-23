import numpy as np

from transcriber.vad import MAX_REGION_SEC, speech_regions

SR = 16000


def tone(sec: float, amp: float = 0.3) -> np.ndarray:
    t = np.arange(int(sec * SR)) / SR
    return (amp * np.sin(2 * np.pi * 220 * t)).astype(np.float32)


def silence(sec: float, noise: float = 0.0) -> np.ndarray:
    rng = np.random.default_rng(0)
    return (noise * rng.standard_normal(int(sec * SR))).astype(np.float32)


def test_regions_follow_speech_with_leading_silence():
    samples = np.concatenate([silence(5), tone(3), silence(10), tone(2), silence(1)])
    regions = speech_regions(samples, SR)
    assert len(regions) == 2
    (s1, e1), (s2, e2) = regions
    assert abs(s1 - 5.0) <= 0.5 and abs(e1 - 8.0) <= 0.5
    assert abs(s2 - 18.0) <= 0.5 and abs(e2 - 20.0) <= 0.5


def test_regions_ignore_background_noise():
    samples = np.concatenate([silence(4, noise=0.002), tone(2), silence(4, noise=0.002)])
    regions = speech_regions(samples, SR)
    assert len(regions) == 1
    assert abs(regions[0][0] - 4.0) <= 0.5


def test_short_pauses_inside_phrase_do_not_split_it():
    samples = np.concatenate([tone(1.5), silence(0.3), tone(1.5)])
    assert len(speech_regions(samples, SR)) == 1


def test_silence_has_no_regions():
    assert speech_regions(silence(10), SR) == []
    assert speech_regions(np.zeros(0, dtype=np.float32), SR) == []


def test_long_speech_is_cut_into_whisper_sized_chunks():
    samples = np.concatenate([tone(25), tone(20, amp=0.05), tone(25)])
    regions = speech_regions(samples, SR)
    assert len(regions) >= 3
    assert all(e - s <= MAX_REGION_SEC + 0.01 for s, e in regions)
    assert abs(regions[0][0]) <= 0.5 and abs(regions[-1][1] - 70.0) <= 0.5
    assert all(b[0] >= a[1] - 1e-6 for a, b in zip(regions, regions[1:]))
