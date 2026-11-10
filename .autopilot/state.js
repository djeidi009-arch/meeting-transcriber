window.STATE =
{
  "version": 2,
  "slug": "mac-app",
  "dir": "2026-11-10-mac-app--wip",
  "title": "Mac-приложение «Транскрибатор»",
  "mode": "semi",
  "depth": "normal",
  "tier": "T2",
  "briefFile": "2026-11-10-brief.md",
  "memoryFile": "AGENTS.md",
  "memoryOwner": "autopilot",
  "skillDir": "/Users/nikitacernomyrdin/.agents/skills/autopilot",
  "baseCommit": null,
  "startedAt": "2026-11-10T19:03:51+07:00",
  "updatedAt": "2026-11-10T19:43:29+07:00",
  "finishedAt": null,
  "stages": [
    {
      "id": "preflight",
      "status": "done",
      "startedAt": "2026-11-10T19:03:51+07:00",
      "finishedAt": "2026-11-10T19:04:07+07:00"
    },
    {
      "id": "manifest",
      "status": "done",
      "startedAt": "2026-11-10T19:04:07+07:00",
      "finishedAt": "2026-11-10T19:04:36+07:00"
    },
    {
      "id": "briefing",
      "status": "done",
      "startedAt": "2026-11-10T19:04:36+07:00",
      "finishedAt": "2026-11-10T19:13:02+07:00"
    },
    {
      "id": "spec",
      "status": "done",
      "startedAt": "2026-11-10T19:13:02+07:00",
      "finishedAt": "2026-11-10T19:41:58+07:00"
    },
    {
      "id": "plan",
      "status": "active",
      "startedAt": "2026-11-10T19:41:58+07:00"
    },
    {
      "id": "build",
      "status": "pending"
    },
    {
      "id": "review",
      "status": "pending"
    },
    {
      "id": "final",
      "status": "pending"
    }
  ],
  "requirements": {
    "total": 52,
    "done": 0,
    "inTicket": 51,
    "inSpec": 0,
    "placeholder": 0,
    "deferred": 1,
    "dropped": 0
  },
  "tickets": [
    {
      "id": "01",
      "title": "Данные для окна: этапы обработки, имена, библиотека встреч",
      "requirements": [
        "R07",
        "R08",
        "R09",
        "R10",
        "R14",
        "R15",
        "R16",
        "R17",
        "R43",
        "R49i",
        "R52i",
        "R30",
        "R32"
      ],
      "blockedBy": [],
      "wave": 1,
      "zone": [
        "transcriber/",
        "tests/",
        "app/Sources/DetectorCore/",
        "app/Sources/selftest/"
      ],
      "review": "да — фундамент",
      "model": "сильная",
      "status": "pending",
      "retries": 0,
      "repairs": 0
    },
    {
      "id": "02",
      "title": "Приложение с окном: Dock, список встреч, поиск",
      "requirements": [
        "R01",
        "R04",
        "R05",
        "R06",
        "R10",
        "R11",
        "R12",
        "R13",
        "R14",
        "R15",
        "R16",
        "R17",
        "R34",
        "R35",
        "R36",
        "R37",
        "R39",
        "R40",
        "R41",
        "R42",
        "R44",
        "R45",
        "R50i",
        "R51i",
        "A01",
        "A03"
      ],
      "blockedBy": [
        "01"
      ],
      "wave": 2,
      "zone": [
        "app/Package.swift",
        "app/Resources/",
        "app/Sources/MeetingTranscriber/",
        "scripts/"
      ],
      "review": "нет",
      "model": "сильная",
      "status": "pending",
      "retries": 0,
      "repairs": 0
    },
    {
      "id": "03",
      "title": "Экран встречи: плеер, транскрипт, summary, имена, экспорт",
      "requirements": [
        "R18",
        "R19",
        "R20",
        "R21",
        "R22",
        "R23",
        "R24",
        "R25",
        "R30",
        "R31",
        "R32",
        "R47",
        "R52i",
        "R02",
        "R03",
        "R37",
        "A02"
      ],
      "blockedBy": [
        "02"
      ],
      "wave": 3,
      "zone": [
        "app/Sources/MeetingTranscriber/UI/",
        "app/Sources/DetectorCore/MeetingDocument.swift",
        "app/Sources/selftest/DocumentTests.swift"
      ],
      "review": "нет",
      "model": "сильная",
      "status": "pending",
      "retries": 0,
      "repairs": 0
    },
    {
      "id": "04",
      "title": "Загрузка перетаскиванием, живая обработка, анимации, скриншоты",
      "requirements": [
        "R26",
        "R27",
        "R28",
        "R29",
        "R38",
        "R46",
        "R48",
        "R39",
        "R02",
        "A03"
      ],
      "blockedBy": [
        "03"
      ],
      "wave": 4,
      "zone": [
        "app/Sources/MeetingTranscriber/",
        "scripts/",
        "docs/screenshots/",
        "README.md"
      ],
      "review": "нет",
      "model": "сильная",
      "status": "pending",
      "retries": 0,
      "repairs": 0
    }
  ],
  "tests": null,
  "debt": {
    "placeholders": [],
    "assumptions": [
      "Анимации рисуются кодом, без Lottie/Rive — на вопрос ответа не было",
      "Экспорт: и DOCX, и PDF — на вопрос ответа не было"
    ],
    "emptyEnv": []
  },
  "additions": [],
  "coverage": {
    "found": 3,
    "fixed": 3,
    "deferred": 0,
    "items": []
  },
  "concerns": [],
  "blind": null,
  "beats": [
    "2026-11-10T19:03:51+07:00",
    "2026-11-10T19:04:07+07:00",
    "2026-11-10T19:04:29+07:00",
    "2026-11-10T19:04:36+07:00",
    "2026-11-10T19:04:58+07:00",
    "2026-11-10T19:11:26+07:00",
    "2026-11-10T19:13:02+07:00",
    "2026-11-10T19:41:58+07:00",
    "2026-11-10T19:43:29+07:00"
  ],
  "rev": 14,
  "waiting": null,
  "waits": [
    {
      "kind": "briefing",
      "from": "2026-11-10T19:04:58+07:00",
      "to": "2026-11-10T19:11:26+07:00"
    }
  ],
  "log": [
    {
      "t": "2026-11-10T19:03:51+07:00",
      "k": "init"
    },
    {
      "t": "2026-11-10T19:04:07+07:00",
      "k": "stage",
      "id": "manifest",
      "act": "start"
    },
    {
      "t": "2026-11-10T19:04:36+07:00",
      "k": "stage",
      "id": "briefing",
      "act": "start"
    },
    {
      "t": "2026-11-10T19:04:58+07:00",
      "k": "ask",
      "kind": "briefing",
      "note": "четыре вопроса — анимации, формат экспорта, хвосты прошлой сборки, ориентиры по виду"
    },
    {
      "t": "2026-11-10T19:11:26+07:00",
      "k": "answered",
      "kind": "briefing"
    },
    {
      "t": "2026-11-10T19:13:02+07:00",
      "k": "add",
      "key": "debt.assumptions",
      "n": 2
    },
    {
      "t": "2026-11-10T19:13:02+07:00",
      "k": "gate",
      "g": "G1",
      "ok": false,
      "open": 52,
      "total": 52
    },
    {
      "t": "2026-11-10T19:13:02+07:00",
      "k": "stage",
      "id": "spec",
      "act": "start"
    },
    {
      "t": "2026-11-10T19:41:58+07:00",
      "k": "gate",
      "g": "G2",
      "ok": true,
      "found": 3,
      "fixed": 3,
      "deferred": 0
    },
    {
      "t": "2026-11-10T19:41:58+07:00",
      "k": "stage",
      "id": "plan",
      "act": "start"
    },
    {
      "t": "2026-11-10T19:43:29+07:00",
      "k": "tier",
      "v": "T2"
    },
    {
      "t": "2026-11-10T19:43:29+07:00",
      "k": "tickets",
      "n": 4
    },
    {
      "t": "2026-11-10T19:43:29+07:00",
      "k": "gate",
      "g": "G3",
      "ok": true,
      "problems": 0
    }
  ],
  "reqList": [
    {
      "id": "R01",
      "text": "«Хочу настоящее приложение для Mac: его можно открыть из Dock или «Программ»»",
      "status": "in-ticket"
    },
    {
      "id": "R02",
      "text": "«оно красивое и подходит для моего портфолио продуктового дизайнера»",
      "status": "in-ticket"
    },
    {
      "id": "R03",
      "text": "«Ориентир по функциям — mymeet.ai, но только то, что мне нужно»",
      "status": "in-ticket"
    },
    {
      "id": "R04",
      "text": "«Значок в строке меню со всем, что есть сейчас: ручная и автоматическая запись встреч»",
      "status": "in-ticket"
    },
    {
      "id": "R05",
      "text": "«Значок в строке меню со всем, что есть сейчас: … уведомления»",
      "status": "in-ticket"
    },
    {
      "id": "R06",
      "text": "«Значок в строке меню со всем, что есть сейчас: … «Загрузить аудио или видео…»»",
      "status": "in-ticket"
    },
    {
      "id": "R07",
      "text": "«Вся обработка — текущий Python-пайплайн (transcriber/): mlx-whisper large-v3-turbo, pyannote, summary через claude -p»",
      "status": "in-ticket"
    },
    {
      "id": "R08",
      "text": "«Локально, без ботов и облака»",
      "status": "in-ticket"
    },
    {
      "id": "R09",
      "text": "«Папки встреч в ~/transcripts и их формат (meta.json, meeting.md, transcript.json, system.m4a/mic.m4a)» — должны остаться",
      "status": "in-ticket"
    },
    {
      "id": "R10",
      "text": "«Старые встречи должны открываться в новом окне»",
      "status": "in-ticket"
    },
    {
      "id": "R11",
      "text": "«Обычное окно приложения: значок в Dock»",
      "status": "in-ticket"
    },
    {
      "id": "R12",
      "text": "«открывается из «Программ» и Spotlight»",
      "status": "in-ticket"
    },
    {
      "id": "R13",
      "text": "«при этом значок в строке меню остаётся»",
      "status": "in-ticket"
    },
    {
      "id": "R14",
      "text": "«Список встреч (как у mymeet: по дням, название, длительность…)»",
      "status": "in-ticket"
    },
    {
      "id": "R15",
      "text": "«статус: идёт запись / в очереди / расшифровывается / готово / ошибка»",
      "status": "in-ticket"
    },
    {
      "id": "R16",
      "text": "«Поиск по названию»",
      "status": "in-ticket"
    },
    {
      "id": "R17",
      "text": "«Поиск по … тексту»",
      "status": "in-ticket"
    },
    {
      "id": "R18",
      "text": "«Экран встречи: плеер (аудио…)»",
      "status": "in-ticket"
    },
    {
      "id": "R19",
      "text": "«плеер (… или видео, если встреча из видеофайла)»",
      "status": "in-ticket"
    },
    {
      "id": "R20",
      "text": "«транскрипт со спикерами и таймкодами»",
      "status": "in-ticket"
    },
    {
      "id": "R21",
      "text": "«синхронизация (нажал на фразу — плеер перемотался…)»",
      "status": "in-ticket"
    },
    {
      "id": "R22",
      "text": "«текущая фраза подсвечивается»",
      "status": "in-ticket"
    },
    {
      "id": "R23",
      "text": "«summary сверху»",
      "status": "in-ticket"
    },
    {
      "id": "R24",
      "text": "«Переименовать встречу»",
      "status": "in-ticket"
    },
    {
      "id": "R25",
      "text": "«Переименовать … спикеров»",
      "status": "in-ticket"
    },
    {
      "id": "R26",
      "text": "«Загрузка файла: перетаскивание видео/аудио в окно»",
      "status": "in-ticket"
    },
    {
      "id": "R27",
      "text": "«и кнопка «Загрузить»»",
      "status": "in-ticket"
    },
    {
      "id": "R28",
      "text": "«Красивая анимация загрузки»",
      "status": "in-ticket"
    },
    {
      "id": "R29",
      "text": "«затем живой прогресс обработки по этапам: извлечение звука → распознавание речи → спикеры → summary»",
      "status": "in-ticket"
    },
    {
      "id": "R30",
      "text": "«Экспорт: Markdown (уже есть)»",
      "status": "in-ticket"
    },
    {
      "id": "R31",
      "text": "«Экспорт: … DOCX или PDF»",
      "status": "in-ticket"
    },
    {
      "id": "R32",
      "text": "«Экспорт: … копировать текст»",
      "status": "in-ticket"
    },
    {
      "id": "R33",
      "text": "«Задел на будущее (не делать сейчас, но не мешать): подключение системного календаря Mac для автозаписи встреч»",
      "status": "deferred",
      "why": "бриф: «не делать сейчас, но не мешать»"
    },
    {
      "id": "R34",
      "text": "«Нативный современный macOS: SwiftUI»",
      "status": "in-ticket"
    },
    {
      "id": "R35",
      "text": "«Liquid Glass (macOS 26+)»",
      "status": "in-ticket"
    },
    {
      "id": "R36",
      "text": "«боковая панель»",
      "status": "in-ticket"
    },
    {
      "id": "R37",
      "text": "«светлая и тёмная темы»",
      "status": "in-ticket"
    },
    {
      "id": "R38",
      "text": "«Анимации — главная «вау»-часть для портфолио: загрузка, обработка, появление транскрипта»",
      "status": "in-ticket"
    },
    {
      "id": "R39",
      "text": "«Кандидаты (все живые, ставятся через Swift Package Manager): Lottie … или Rive …; Pow …; Vortex …; Inferno …; DSWaveformImage …»",
      "status": "in-ticket"
    },
    {
      "id": "R40",
      "text": "«Выбрать минимальный набор, который даёт сильный результат, а не всё сразу»",
      "status": "in-ticket"
    },
    {
      "id": "R41",
      "text": "«macOS 27 на Apple Silicon»",
      "status": "in-ticket"
    },
    {
      "id": "R42",
      "text": "«Xcode нет, только Command Line Tools: сборка через SwiftPM, как сейчас (app/Package.swift, scripts/build_app.sh)»",
      "status": "in-ticket"
    },
    {
      "id": "R43",
      "text": "«Существующие проверки (make check) должны продолжать проходить»",
      "status": "in-ticket"
    },
    {
      "id": "R44",
      "text": "«Весь текст интерфейса — по-русски»",
      "status": "in-ticket"
    },
    {
      "id": "R45",
      "text": "«Приложение открывается из Dock, показывает мои реальные встречи из ~/transcripts»",
      "status": "in-ticket"
    },
    {
      "id": "R46",
      "text": "«загружает видео перетаскиванием с анимацией и живым прогрессом»",
      "status": "in-ticket"
    },
    {
      "id": "R47",
      "text": "«проигрывает запись с синхронным транскриптом»",
      "status": "in-ticket"
    },
    {
      "id": "R48",
      "text": "«Его не стыдно показать в портфолио: есть скриншоты светлой и тёмной темы»",
      "status": "in-ticket"
    },
    {
      "id": "R49i",
      "text": "(подразумевается) живой прогресс по этапам требует, чтобы Python-пайплайн сообщал приложению текущий этап",
      "status": "in-ticket"
    },
    {
      "id": "R50i",
      "text": "(подразумевается) у приложения должна быть собственная иконка для Dock и «Программ»",
      "status": "in-ticket"
    },
    {
      "id": "R51i",
      "text": "(подразумевается) окно и значок в строке меню — одна программа: запись, начатая из меню, видна в списке окна сразу",
      "status": "in-ticket"
    },
    {
      "id": "R52i",
      "text": "(подразумевается) переименование спикеров и встречи сохраняется в файлах встречи и переживает перезапуск",
      "status": "in-ticket"
    }
  ],
  "gates": {
    "G1": {
      "ok": false,
      "at": "2026-11-10T19:13:02+07:00",
      "open": 52,
      "total": 52
    },
    "G2": {
      "ok": true,
      "at": "2026-11-10T19:41:58+07:00",
      "found": 3,
      "fixed": 3,
      "deferred": 0
    },
    "G3": {
      "ok": true,
      "at": "2026-11-10T19:43:29+07:00",
      "problems": 0
    }
  },
  "result": null
}
