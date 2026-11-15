from datetime import datetime, timedelta, timezone

import pytest

from ytm_migrate.navidrome import ListenBrainzLinkedError, Navidrome
from ytm_migrate.state import State
from ytm_migrate.takeout import LibrarySong, Play

START = datetime(2024, 1, 1, tzinfo=timezone.utc)
BASE = "http://nd"


class Response:
    def __init__(self, payload, status_code=200):
        self.payload = payload
        self.status_code = status_code

    def json(self):
        return self.payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(self.status_code)


class FakeSession:
    def __init__(self, songs=(), linked=False, listenbrainz_status=200):
        self.songs = list(songs)
        self.linked = linked
        self.listenbrainz_status = listenbrainz_status
        self.playlists = {}
        self.owners = {}
        self.calls = []
        self.next_id = 1

    def get(self, url, params=None, headers=None, timeout=None):
        path = url.removeprefix(BASE)
        params = list(params or [])
        self.calls.append((path, params, headers))
        assert headers == {"Remote-User": "jesse"}
        assert ("c", "ytm-migrate") in params and ("f", "json") in params
        assert not any(k in ("u", "p") for k, _ in params)
        q = {}
        for k, v in params:
            q.setdefault(k, []).append(v)
        if path == "/api/listenbrainz/link":
            return Response({"status": self.linked}, self.listenbrainz_status)
        if path == "/rest/search3":
            offset, count = int(q["songOffset"][0]), int(q["songCount"][0])
            return Response(sub({"searchResult3": {"song": self.songs[offset : offset + count]}}))
        if path == "/rest/getPlaylists":
            listed = [{"id": i, "name": p["name"], "owner": self.owners.get(i, "jesse")} for i, p in self.playlists.items()]
            return Response(sub({"playlists": {"playlist": listed}}))
        if path == "/rest/getPlaylist":
            p = self.playlists[q["id"][0]]
            return Response(sub({"playlist": {"id": q["id"][0], "name": p["name"], "entry": [{"id": s} for s in p["songs"]]}}))
        if path == "/rest/createPlaylist":
            pid = q.get("playlistId", [None])[0]
            if pid is None:
                pid = f"pl{self.next_id}"
                self.next_id += 1
            assert "playlistId" not in q
            self.playlists[pid] = {"name": q.get("name", [self.playlists.get(pid, {}).get("name")])[0], "songs": q.get("songId", [])}
            return Response(sub({}))
        if path == "/rest/updatePlaylist":
            pid = q["playlistId"][0]
            assert self.owners.get(pid, "jesse") == "jesse"
            self.playlists[pid]["songs"] = self.playlists[pid]["songs"] + q.get("songIdToAdd", [])
            return Response(sub({}))
        return Response(sub({}))

    def paths(self, name):
        return [c for c in self.calls if c[0] == f"/rest/{name}"]


def sub(body):
    return {"subsonic-response": {"status": "ok", **body}}


def song(id, artist, title, album="", mbid=""):
    return {"id": id, "artist": artist, "title": title, "album": album, "musicBrainzId": mbid}


def make(session):
    return Navidrome(BASE, "jesse", session=session)


def make_state(tmp_path):
    state = State(tmp_path / "s.db")
    state.add_plays([Play("v1", START, "Alpha", "Band - Topic"), Play("v1", START + timedelta(seconds=9), "Alpha", "Band - Topic")])
    state.set_playlists({"Mix": ["v1", "v2", "v3"]})
    state.set_liked([LibrarySong("v1", "Alpha", "A", ["Band"])])
    state.set_identity("v1", "mbid-1", None, None, "identified", "Band", "Alpha", "A")
    state.set_identity("v2", "other artist|beta", None, None, "queued", "Other Artist", "Beta")
    state.set_identity("v3", "gamma-mbid", None, None, "identified", "Nobody", "Gamma")
    return state


def test_matches_by_mbid_then_artist_title():
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1"), song("b", "Other  Artist", "Beta (Official Video)")])
    index = make(session).index()
    assert index.find("mbid-1", "Zzz", "Zzz") == "a"
    assert index.find("unknown", "Other Artist", "Beta") == "b"
    assert index.find(None, "Nobody", "Gamma") is None


def test_index_pages_until_short_page():
    session = FakeSession([song(str(i), "A", f"T{i}") for i in range(1200)])
    index = make(session).index()
    assert len(session.paths("search3")) == 3
    assert index.find(None, "A", "T1199") == "1199"


def test_playlist_rerun_does_not_duplicate_entries(tmp_path):
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1"), song("b", "Other Artist", "Beta")])
    state = make_state(tmp_path)
    nd = make(session)
    first = nd.apply(state, nd.index())
    assert first.playlists_created == 1
    nd.apply(state, nd.index())
    second = nd.apply(state, nd.index())
    assert second.playlists_created == 0
    assert len(session.playlists) == 1
    assert list(session.playlists.values())[0]["songs"] == ["a", "b"]


def test_pending_items_applied_once_when_track_appears(tmp_path):
    session = FakeSession([])
    state = make_state(tmp_path)
    nd = make(session)
    r1 = nd.apply(state, nd.index())
    assert (r1.scrobbles, r1.stars, r1.playlists_created) == (0, 0, 0)
    assert r1.pending > 0
    assert not session.paths("scrobble") and not session.paths("star")
    session.songs = [song("a", "X", "Y", mbid="mbid-1")]
    r2 = nd.apply(state, nd.index())
    assert (r2.scrobbles, r2.stars, r2.playlists_created) == (2, 1, 1)
    times = sorted(str(dict(p)["time"]) for _, p, _ in session.paths("scrobble"))
    assert times == [str(int(START.timestamp() * 1000)), str(int((START + timedelta(seconds=9)).timestamp() * 1000))]
    assert all(str(dict(p)["submission"]) == "true" for _, p, _ in session.paths("scrobble"))
    r3 = nd.apply(state, nd.index())
    assert (r3.scrobbles, r3.stars) == (0, 0)
    assert len(session.paths("scrobble")) == 2 and len(session.paths("star")) == 1


def test_refuses_when_listenbrainz_linked(tmp_path):
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1")], linked=True)
    state = make_state(tmp_path)
    nd = make(session)
    with pytest.raises(ListenBrainzLinkedError):
        nd.apply(state, nd.index())
    assert not session.paths("scrobble") and not session.paths("createPlaylist")


def test_listenbrainz_disabled_is_not_linked(tmp_path):
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1")], listenbrainz_status=404)
    state = make_state(tmp_path)
    nd = make(session)
    assert nd.apply(state, nd.index()).scrobbles == 2


def test_has_album_detects_cd_rip():
    session = FakeSession([song("a", "The Band", "Alpha", album="Great Album (Deluxe Edition)")])
    index = make(session).index()
    assert index.has_album("the band", "great album")
    assert not index.has_album("the band", "other")


def test_playlist_update_appends_and_keeps_existing_entries(tmp_path):
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1"), song("b", "Other Artist", "Beta"), song("g", "Nobody", "Gamma", mbid="gamma-mbid")])
    session.playlists["p1"] = {"name": "Mix", "songs": ["z", "b"]}
    state = make_state(tmp_path)
    nd = make(session)
    report = nd.apply(state, nd.index())
    assert (report.playlists_created, report.playlists_updated) == (0, 1)
    assert session.playlists["p1"]["songs"] == ["z", "b", "a", "g"]
    assert not [c for c in session.paths("createPlaylist")]
    again = nd.apply(state, nd.index())
    assert again.playlists_updated == 0
    assert session.playlists["p1"]["songs"] == ["z", "b", "a", "g"]


def test_foreign_playlist_with_same_name_is_left_alone(tmp_path):
    session = FakeSession([song("a", "X", "Y", mbid="mbid-1")])
    session.playlists["p9"] = {"name": "Mix", "songs": ["q"]}
    session.owners["p9"] = "someone"
    state = make_state(tmp_path)
    nd = make(session)
    report = nd.apply(state, nd.index())
    assert report.playlists_created == 1
    assert session.playlists["p9"]["songs"] == ["q"]
    assert not session.paths("updatePlaylist")


def test_has_album_matches_album_artist_of_compilation_tracks():
    session = FakeSession(
        [
            {**song("a", "Guest Singer", "One", album="Big Hits"), "albumArtist": "Various Artists"},
            {**song("b", "Other Guest", "Two", album="Duets"), "albumArtists": [{"id": "x", "name": "The Band"}]},
            {**song("c", "Feat Person", "Three", album="Solo"), "displayAlbumArtist": "Solo Act"},
        ]
    )
    index = make(session).index()
    assert index.has_album("various artists", "big hits")
    assert index.has_album("guest singer", "big hits")
    assert index.has_album("the band", "duets")
    assert index.has_album("solo act", "solo")
