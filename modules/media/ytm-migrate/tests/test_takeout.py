from datetime import timezone

from ytm_migrate import takeout
from ytm_migrate.state import State

ALLOW = {"Chill Music", "Favorites"}


def test_only_youtube_music_history_is_read(takeout_zip):
    result = takeout.read(takeout_zip, ALLOW)
    assert len(result.history) == 9
    assert all("youtube.com" not in p.video_id for p in result.history)


def test_play_has_video_id_and_utc_time(takeout_zip):
    play = takeout.read(takeout_zip, ALLOW).history[0]
    assert play.video_id == "H4rBLGmbe80"
    assert play.played_at.tzinfo == timezone.utc
    assert play.title == "Soul to Squeeze"
    assert play.channel == "Red Hot Chili Peppers - Topic"


def test_playlists_keep_order(takeout_zip):
    playlists = takeout.read(takeout_zip, ALLOW).playlists
    assert playlists["Chill Music"][:2] == ["Cx3QmqV2pHg", "uZAsfB1Np-8"]
    assert playlists["Favorites"][:2] == ["QQkVvs_oMMU", "CCLA_EG9BWo"]


def test_leading_space_before_dash_id_is_stripped(takeout_zip):
    assert "-BakWVXHSug" in takeout.read(takeout_zip, ALLOW).playlists["Chill Music"]


def test_playlists_outside_allowlist_ignored(takeout_zip):
    assert set(takeout.read(takeout_zip, ALLOW).playlists) == ALLOW


def test_liked_list_read(takeout_zip):
    liked = takeout.read(takeout_zip, ALLOW).liked
    assert liked[0].video_id == "n50LrYEcqo4"
    assert liked[0].title == "Cheer Up, Boys (Your Make Up Is Running)"
    assert liked[0].album == "Echoes, Silence, Patience & Grace"
    assert liked[0].artists == ["Foo Fighters"]


def test_reimport_same_zip_adds_nothing(takeout_zip, tmp_path):
    state = State(tmp_path / "state.db")
    history = takeout.read(takeout_zip, ALLOW).history
    assert state.add_plays(history) == len(history)
    assert state.add_plays(history) == 0


def test_allowlisted_playlist_without_videos_file_skipped(takeout_zip, tmp_path):
    import zipfile

    stripped = tmp_path / "stripped.zip"
    with zipfile.ZipFile(takeout_zip) as src, zipfile.ZipFile(stripped, "w") as dst:
        for item in src.infolist():
            if not item.filename.endswith("Chill Music-Videos.csv"):
                dst.writestr(item, src.read(item))
    playlists = takeout.read(stripped, ALLOW | {"Absent"}).playlists
    assert set(playlists) == {"Favorites"}


def test_allowlisted_playlist_missing_from_export_warns(takeout_zip, capsys):
    takeout.read(takeout_zip, ALLOW | {"Absent"})
    err = capsys.readouterr().err
    assert "Absent" in err
    assert "Favorites" not in err
