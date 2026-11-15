from datetime import datetime, timezone

import pytest

from ytm_migrate.state import State
from ytm_migrate.takeout import LibrarySong, Play


@pytest.fixture
def state(tmp_path):
    return State(tmp_path / "state.db")


def play(video_id="a", minute=0):
    return Play(video_id, datetime(2026, 1, 1, 0, minute, tzinfo=timezone.utc), "T", "Artist - Topic")


def test_add_plays_creates_new_songs(state):
    state.add_plays([play()])
    [song] = state.songs()
    assert (song.video_id, song.status, song.artist_name) == ("a", "new", "Artist")


def test_set_identity_updates_and_keeps_unset_fields(state):
    state.add_plays([play()])
    state.set_identity("a", "key", "am", "rg", "identified", album="Alb")
    state.set_identity("a", "key", "am", "rg", "identified")
    [song] = state.songs()
    assert (song.song_key, song.artist_mbid, song.release_group_mbid) == ("key", "am", "rg")
    assert (song.title, song.album, song.artist_name) == ("T", "Alb", "Artist")


def test_set_playlists_replaces_wholesale(state):
    state.set_playlists({"A": ["x", "y"], "B": ["z"]})
    state.set_playlists({"A": ["y", "x"]})
    assert state.playlists() == {"A": ["y", "x"]}


def test_liked_roundtrip(state):
    liked = [LibrarySong("v", "Title", "Album", ["One", "Two"])]
    state.set_liked(liked)
    state.set_liked(liked)
    assert state.liked() == liked


def test_pending_listens_listenbrainz_gets_all_navidrome_only_identified(state):
    state.add_plays([play("a"), play("b", 1)])
    state.set_identity("a", "k", "m", "r", "identified")
    assert [p.video_id for p in state.pending_listens("listenbrainz")] == ["a", "b"]
    assert [p.video_id for p in state.pending_listens("navidrome")] == ["a"]
    pending = state.pending_listens("listenbrainz")
    state.mark_sent("listenbrainz", [(p.video_id, p.played_at) for p in pending])
    assert state.pending_listens("listenbrainz") == []
    assert len(state.pending_listens("navidrome")) == 1


def test_set_liked_fills_metadata_on_existing_song(state):
    state.add_plays([play("a")])
    state.set_liked([LibrarySong("a", "Real Title", "Real Album", ["Real Artist"])])
    [song] = state.songs()
    assert (song.title, song.album, song.artist_name) == ("Real Title", "Real Album", "Real Artist")


def test_applied_markers(state):
    assert not state.is_applied("playlist", "A")
    state.mark_applied("playlist", "A")
    assert state.is_applied("playlist", "A")


def test_review_items_and_set_status(state):
    state.add_plays([play()])
    state.set_status("a", "review")
    assert [s.video_id for s in state.review_items()] == ["a"]
    state.set_status("a", "skipped")
    assert state.review_items() == []


def test_cached_fetches_once_and_survives_reopen(tmp_path):
    calls = []

    def fetch():
        calls.append(1)
        return {"answer": [42]}

    first = State(tmp_path / "s.db")
    assert first.cached("mb.search", '["x"]', fetch) == {"answer": [42]}
    assert first.cached("mb.search", '["x"]', fetch) == {"answer": [42]}
    assert State(tmp_path / "s.db").cached("mb.search", '["x"]', fetch) == {"answer": [42]}
    assert len(calls) == 1


def test_cached_stores_none_results(state):
    calls = []
    state.cached("yt.song", '["v"]', lambda: calls.append(1))
    state.cached("yt.song", '["v"]', lambda: calls.append(1))
    assert calls == [1]


def test_review_detail_roundtrip(state):
    state.add_plays([play()])
    assert state.review_detail("a") is None
    state.set_review("a", "why", [{"artist_mbid": "m"}])
    state.set_review("a", "why not", [])
    assert state.review_detail("a") == ("why not", [])


def test_play_counts_per_video(state):
    state.add_plays([play("a"), play("a", 1), play("b", 2)])
    assert state.play_counts() == {"a": 2, "b": 1}


def test_not_music_plays_are_never_sent_to_listenbrainz(state):
    state.add_plays([play("a"), play("b", 1), play("c", 2), play("d", 3)])
    state.set_status("b", "not_music")
    state.set_status("c", "review")
    state.set_status("d", "skipped")
    assert [p.video_id for p in state.pending_listens("listenbrainz")] == ["a", "c", "d"]


def test_untrimmed_song_ids_from_older_runs_are_dropped(tmp_path):
    path = tmp_path / "state.db"
    State(path).set_playlists({"Chill Music": [" -BakWVXHSug", "abc"]})
    state = State(path)
    assert [s.video_id for s in state.songs()] == ["abc"]


def test_interrupted_confirmations_go_back_to_review(tmp_path):
    path = tmp_path / "state.db"
    State(path).set_identity("v1", "k1", None, "rg", "confirming")
    state = State(path)
    state.reset_confirming()
    assert [s.status for s in state.songs()] == ["review"]


def test_confirm_messages_are_shown_once(tmp_path):
    state = State(tmp_path / "state.db")
    state.add_confirm_message("v1", "boom", error=True)
    assert state.pop_confirm_messages() == [("v1", "boom", True)]
    assert state.pop_confirm_messages() == []
