"""CLI: python -m transcriber process|resummarize <папка встречи>."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import config, pipeline


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="transcriber", description="Обработка записи встречи")
    parser.add_argument("command", choices=["process", "resummarize"])
    parser.add_argument("meeting_dir", type=Path)
    args = parser.parse_args(argv)

    try:
        cfg = config.load()
        if args.command == "process":
            pipeline.process(args.meeting_dir, cfg)
        else:
            pipeline.resummarize(args.meeting_dir, cfg)
    except KeyboardInterrupt:
        print("Обработка прервана", file=sys.stderr)
        return 1
    except Exception as exc:  # одна строка по-русски для уведомления
        print(pipeline.error_message(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
