window.STATE =
{
  "version": 2,
  "slug": "meeting-transcriber",
  "dir": "2026-10-23-meeting-transcriber--wip",
  "title": "Транскрибатор встреч",
  "mode": "semi",
  "depth": "normal",
  "tier": "T1",
  "briefFile": "2026-10-23-brief.md",
  "memoryFile": "AGENTS.md",
  "memoryOwner": "autopilot",
  "skillDir": "/Users/nikitacernomyrdin/.agents/skills/autopilot",
  "baseCommit": null,
  "startedAt": "2026-10-23T15:34:48+07:00",
  "updatedAt": "2026-10-23T15:42:53+07:00",
  "finishedAt": null,
  "stages": [
    {
      "id": "preflight",
      "status": "done",
      "startedAt": "2026-10-23T15:34:48+07:00",
      "finishedAt": "2026-10-23T15:35:13+07:00"
    },
    {
      "id": "manifest",
      "status": "done",
      "startedAt": "2026-10-23T15:35:13+07:00",
      "finishedAt": "2026-10-23T15:35:36+07:00"
    },
    {
      "id": "briefing",
      "status": "done",
      "startedAt": "2026-10-23T15:35:36+07:00",
      "finishedAt": "2026-10-23T15:40:34+07:00"
    },
    {
      "id": "spec",
      "status": "done",
      "startedAt": "2026-10-23T15:40:34+07:00",
      "finishedAt": "2026-10-23T15:42:47+07:00"
    },
    {
      "id": "plan",
      "status": "active",
      "startedAt": "2026-10-23T15:42:47+07:00"
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
    "total": 13,
    "done": 0,
    "inTicket": 13,
    "inSpec": 0,
    "placeholder": 0,
    "deferred": 0,
    "dropped": 0
  },
  "tickets": [
    {
      "id": "01",
      "title": "Обработка записи: текст, спикеры, summary",
      "requirements": [
        "R07",
        "R08",
        "R09",
        "R11i",
        "R12i"
      ],
      "blockedBy": [],
      "wave": 1,
      "zone": [
        "transcriber/",
        "tests/",
        "pyproject.toml"
      ],
      "review": "нет",
      "model": "сильная",
      "status": "pending",
      "retries": 0,
      "repairs": 0
    },
    {
      "id": "02",
      "title": "Приложение в строке меню: детект встречи и запись",
      "requirements": [
        "R01",
        "R02",
        "R03",
        "R04",
        "R05",
        "R06",
        "R10i",
        "R11i",
        "R13i",
        "R07",
        "A01"
      ],
      "blockedBy": [],
      "wave": 1,
      "zone": [
        "app/",
        "scripts/",
        "Makefile",
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
    "assumptions": [],
    "emptyEnv": []
  },
  "additions": [],
  "coverage": {
    "found": 0,
    "fixed": 0,
    "deferred": 0,
    "items": []
  },
  "concerns": [],
  "blind": null,
  "beats": [
    "2026-10-23T15:34:48+07:00",
    "2026-10-23T15:35:13+07:00",
    "2026-10-23T15:35:36+07:00",
    "2026-10-23T15:38:36+07:00",
    "2026-10-23T15:40:34+07:00",
    "2026-10-23T15:42:47+07:00",
    "2026-10-23T15:42:48+07:00",
    "2026-10-23T15:42:53+07:00"
  ],
  "rev": 13,
  "waiting": null,
  "waits": [
    {
      "kind": "briefing",
      "from": "2026-10-23T15:35:36+07:00",
      "to": "2026-10-23T15:38:36+07:00"
    }
  ],
  "log": [
    {
      "t": "2026-10-23T15:34:48+07:00",
      "k": "init"
    },
    {
      "t": "2026-10-23T15:35:13+07:00",
      "k": "stage",
      "id": "manifest",
      "act": "start"
    },
    {
      "t": "2026-10-23T15:35:36+07:00",
      "k": "stage",
      "id": "briefing",
      "act": "start"
    },
    {
      "t": "2026-10-23T15:35:36+07:00",
      "k": "ask",
      "kind": "briefing",
      "note": "четыре вопроса — как ловить встречу, автостарт, где делать summary, куда сохранять"
    },
    {
      "t": "2026-10-23T15:38:36+07:00",
      "k": "answered",
      "kind": "briefing"
    },
    {
      "t": "2026-10-23T15:40:34+07:00",
      "k": "gate",
      "g": "G1",
      "ok": false,
      "open": 13,
      "total": 13
    },
    {
      "t": "2026-10-23T15:40:34+07:00",
      "k": "stage",
      "id": "spec",
      "act": "start"
    },
    {
      "t": "2026-10-23T15:42:47+07:00",
      "k": "stage",
      "id": "plan",
      "act": "start"
    },
    {
      "t": "2026-10-23T15:42:48+07:00",
      "k": "tier",
      "v": "T1"
    },
    {
      "t": "2026-10-23T15:42:48+07:00",
      "k": "tickets",
      "n": 2
    },
    {
      "t": "2026-10-23T15:42:48+07:00",
      "k": "gate",
      "g": "G3",
      "ok": true,
      "problems": 0
    },
    {
      "t": "2026-10-23T15:42:53+07:00",
      "k": "gate",
      "g": "G2",
      "ok": true,
      "found": 0,
      "fixed": 0,
      "deferred": 0
    }
  ],
  "reqList": [
    {
      "id": "R01",
      "text": "«будет определять, что я нахожусь на встрече. Либо, если это проще технически, я могу добавлять встречи»",
      "status": "in-ticket"
    },
    {
      "id": "R02",
      "text": "«в Zoom»",
      "status": "in-ticket"
    },
    {
      "id": "R03",
      "text": "«в Google Meet»",
      "status": "in-ticket"
    },
    {
      "id": "R04",
      "text": "«в Яндекс.Телемасте»",
      "status": "in-ticket"
    },
    {
      "id": "R05",
      "text": "«в ContourTalk»",
      "status": "in-ticket"
    },
    {
      "id": "R06",
      "text": "«в общем, в любых известных программах для аудиоконференций»",
      "status": "in-ticket"
    },
    {
      "id": "R07",
      "text": "«Он будет транскрибировать встречу»",
      "status": "in-ticket"
    },
    {
      "id": "R08",
      "text": "«желательно разбивать по спикерам. Хотя бы просто спикер 1, спикер 2»",
      "status": "in-ticket"
    },
    {
      "id": "R09",
      "text": "«И выдавать краткое summary по встрече. Если технически проще без summary, это тоже подойдет»",
      "status": "in-ticket"
    },
    {
      "id": "R10i",
      "text": "(подразумевается) в записи слышны и мой голос, и собеседники",
      "status": "in-ticket"
    },
    {
      "id": "R11i",
      "text": "(подразумевается) транскрипт и summary где-то сохраняются и их можно открыть",
      "status": "in-ticket"
    },
    {
      "id": "R12i",
      "text": "(подразумевается) встречи на русском языке",
      "status": "in-ticket"
    },
    {
      "id": "R13i",
      "text": "(подразумевается) записью можно управлять: видно, что идёт запись, её можно остановить",
      "status": "in-ticket"
    }
  ],
  "gates": {
    "G1": {
      "ok": false,
      "at": "2026-10-23T15:40:34+07:00",
      "open": 13,
      "total": 13
    },
    "G3": {
      "ok": true,
      "at": "2026-10-23T15:42:48+07:00",
      "problems": 0
    },
    "G2": {
      "ok": true,
      "at": "2026-10-23T15:42:53+07:00",
      "found": 0,
      "fixed": 0,
      "deferred": 0
    }
  },
  "result": null
}
