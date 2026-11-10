import json

from transcriber import userdata


def test_load_title_and_speaker_names(tmp_path):
    (tmp_path / "user.json").write_text(
        json.dumps({"title": "Планёрка по релизу", "speakers": {"Спикер 1": "Аня", "Я": "Никита"}}, ensure_ascii=False)
    )
    user = userdata.load(tmp_path)
    assert user.title == "Планёрка по релизу"
    assert user.name("Спикер 1") == "Аня" and user.name("Я") == "Никита"
    assert user.name("Спикер 2") == "Спикер 2"  # не переименован — метка как есть


def test_missing_broken_or_wrong_shape_is_empty(tmp_path):
    assert userdata.load(tmp_path) == userdata.UserData()
    for text in ("{не json", "[1, 2]", json.dumps({"title": 5, "speakers": ["x"]}), json.dumps({"title": "  ", "speakers": {"Я": ""}})):
        (tmp_path / "user.json").write_text(text)
        user = userdata.load(tmp_path)
        assert user.title is None and user.name("Я") == "Я", text
