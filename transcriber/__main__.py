"""CLI: python -m transcriber process|resummarize <папка встречи>."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import config, pipeline

# Код выхода: встреча расшифрована, meeting.md записан, но summary не получилось.
# Swift-часть (ProcessingQueue) показывает по нему уведомление «Меню → Повторить summary».
EXIT_SUMMARY_FAILED = 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="transcriber", description="Обработка записи встречи")
    parser.add_argument("command", choices=["process", "resummarize"])
    parser.add_argument("meeting_dir", type=Path)
    args = parser.parse_args(argv)

    try:
        cfg = config.load()
        run = pipeline.process if args.command == "process" else pipeline.resummarize
        summary_error = run(args.meeting_dir, cfg)
        if summary_error:
            print(" ".join(f"Summary не удалось сделать: {summary_error}".split()), file=sys.stderr)
            return EXIT_SUMMARY_FAILED
    except KeyboardInterrupt:
        print("Обработка прервана", file=sys.stderr)
        return 1
    except Exception as exc:  # одна строка по-русски для уведомления
        print(pipeline.error_message(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
