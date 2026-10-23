"""Общие структуры данных обработки."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Segment:
    start: float
    end: float
    text: str


@dataclass(frozen=True)
class Turn:
    start: float
    end: float
    speaker: str


@dataclass(frozen=True)
class Utterance:
    start: float
    end: float
    speaker: str
    text: str
