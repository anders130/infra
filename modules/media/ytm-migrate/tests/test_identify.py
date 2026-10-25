import json
from datetime import datetime, timezone
from pathlib import Path

import pytest

from ytm_migrate.identify import (
    Known,
    MusicBrainz,
    identify,
    identify_new,
    lookup_key,
    select,
)
from ytm_migrate.state import State
from ytm_migrate.takeout import LibrarySong, Play

API = Path(__file__).parent / "fixtures" / "api"

DIRE_STRAITS = "614e3804-7d34-41ba-857f-811bad7c2b7a"
ALAN_PARSONS_PROJECT = "f98711e5-06f7-43ed-8239-da0f61a9c460"
TOMMY_EMMANUEL = "50c629c6-6f22-4bf9-a3c2-f2855e6704be"
TALES_OF_MYSTERY = "5d8f45de-ec81-36c7-88d1-a232193fbf15"
BLOOD_SUGAR_SEX_MAGIK = "68bee70d-b425-3813-aca7-dd7b912c3d11"


class Recorded:
    def __init__(self, *names):
        self.responses = {}
        for name in names:
            self.responses.update(json.loads((API / f"{name}.json").read_text()))
        self.calls = []

    def __getattr__(self, method):
        def call(*args):
            key = lookup_key(method, args)
            self.calls.append(key)
            return self.responses[key]

        return call


@pytest.fixture
def yt():
    return Recorded("ytmusic")


@pytest.fixture
def mb():
    return Recorded("musicbrainz")


@pytest.fixture
def state(tmp_path):
    return State(tmp_path / "state.db")


def history(title, artist):
    return Known(title, [artist])


def liked(title, album, *artists):
    return Known(title, list(artists), album, liked=True)


def play(video_id, minute=0, title="T", channel="Red Hot Chili Peppers - Topic"):
    return Play(video_id, datetime(2026, 1, 1, 0, minute, tzinfo=timezone.utc), title, channel)


def test_topic_channel_single_studio_album_is_confident(yt, mb):
    identity = identify("Y2Duog7ZWcA", yt, mb, history("Down To The Waterline", "Dire Straits"))
    assert identity.kind == "confident"
    assert identity.artist_mbid == DIRE_STRAITS
    assert identity.release_group_mbid == "0c9bc273-a9e9-3290-b423-c61b9f8d20bc"

    identity = identify("N47SWUcYhQU", yt, mb, history("Mammagamma", "The Alan Parsons Project"))
    assert (identity.kind, identity.artist_mbid, identity.release_group_mbid) == (
        "confident",
        ALAN_PARSONS_PROJECT,
        "c9137ca5-26bd-3374-bebc-a813fbfe9c4f",
    )


def test_liked_song_uses_library_metadata_without_youtube(yt, mb):
    identity = identify("vB8dweYCLes", yt, mb, liked("I Robot", "I Robot", "The Alan Parsons Project"))
    assert (identity.kind, identity.release_group_mbid) == ("confident", "bc5d259c-9323-3721-a346-5d379338eddf")
    assert yt.calls == []


def test_multi_artist_song_is_identified_via_first_artist(yt, mb):
    identity = identify(
        "XsCPCmpNeto",
        yt,
        mb,
        liked("(Sittin' On) The Dock of the Bay", "Accomplice One", "Tommy Emmanuel", "J.D. Simo"),
    )
    assert (identity.kind, identity.artist_mbid, identity.release_group_mbid) == (
        "confident",
        TOMMY_EMMANUEL,
        "bc75b2ec-d39a-4677-af06-fe343479bf51",
    )


def test_release_group_credited_to_a_collaboration_goes_to_review(yt):
    mb = Recorded("synthetic_collaboration")
    identity = identify("synthCollab", yt, mb, liked("Duet", "Together", "Solo Artist", "Partner"))
    assert identity.kind == "review"
    assert "Solo Artist & Partner" in identity.reason
    assert [c.release_group_mbid for c in identity.candidates] == ["rg-together"]
    assert [(c.credit_name, c.credit_artist) for c in identity.candidates] == [("Solo Artist & Partner", "Solo Artist")]


def test_two_artists_same_name_goes_to_review(yt):
    mb = Recorded("synthetic_same_name")
    identity = identify("synthTwins", yt, mb, liked("Song", "Album", "Twin"))
    assert identity.kind == "review"
    assert identity.artist_mbid is None
    assert "ambiguous" in identity.reason
    assert "US punk band" in identity.reason
    assert {c.artist_mbid for c in identity.candidates} == {"twin-a", "twin-b"}
    assert identity.song_key == "twin|song"


def test_name_match_without_perfect_score_needs_clear_margin(yt):
    mb = Recorded("synthetic_near_names")
    clear = identify("synthBey", yt, mb, liked("Formation", "Lemonade", "Beyonce"))
    assert (clear.kind, clear.artist_mbid, clear.release_group_mbid) == ("confident", "bey", "rg-lemonade")
    close = identify("synthMono", yt, mb, liked("Ashes", "Hymn", "Mono"))
    assert close.kind == "review"
    assert "ambiguous" in close.reason
    assert {c.artist_mbid for c in close.candidates} == {"mono-a", "mono-b"}


def test_deluxe_and_standard_goes_to_review(yt, mb):
    remix = identify(
        "D1E9mjvGYq8",
        yt,
        mb,
        liked(
            "(The System Of) Doctor Tarr And Professor Fether (1987 Remix)",
            "Tales Of Mystery And Imagination - Edgar Allan Poe (1987 Remix)",
            "The Alan Parsons Project",
            "Alan Parsons",
            "Eric Woolfson",
        ),
    )
    original = identify(
        "IEnc5F2eHZw",
        yt,
        mb,
        liked(
            "(The System Of) Doctor Tarr And Professor Fether",
            "Tales Of Mystery And Imagination (Original 1976 Version)",
            "The Alan Parsons Project",
        ),
    )
    for identity in [remix, original]:
        assert identity.kind == "review"
        assert identity.release_group_mbid is None
        assert identity.artist_mbid == ALAN_PARSONS_PROJECT
        assert identity.candidates[0].release_group_mbid == TALES_OF_MYSTERY
        assert len(identity.candidates) <= 5
        assert "no studio album titled" in identity.reason
    assert remix.song_key != original.song_key

    editions = Recorded("synthetic_editions")
    both = identify("synthATV", Recorded("synthetic_editions"), editions, history("Song", "Band"))
    assert both.kind == "review"
    assert "2 studio albums titled" in both.reason
    assert {c.release_group_mbid for c in both.candidates} >= {"rg-record", "rg-record-deluxe"}


def test_edition_qualifier_on_album_resolves_to_studio_release_group(yt, mb):
    identity = identify("4UnU3r0M3zg", yt, mb, history("Under the Bridge", "Red Hot Chili Peppers"))
    assert (identity.kind, identity.artist_mbid, identity.release_group_mbid) == (
        "confident",
        "8bfac288-ccc5-448d-9573-c33ea2aa5c30",
        BLOOD_SUGAR_SEX_MAGIK,
    )


def test_exact_album_title_wins_over_edition_stripping(yt):
    editions = Recorded("synthetic_editions")
    identity = identify("synthDeluxe", yt, editions, liked("Song", "Record (Deluxe Edition)", "Band"))
    assert (identity.kind, identity.release_group_mbid) == ("confident", "rg-record-deluxe")


def test_soundtrack_album_goes_to_review(yt, mb):
    identity = identify("H4rBLGmbe80", yt, mb, history("Soul to Squeeze", "Red Hot Chili Peppers"))
    assert identity.kind == "review"
    assert "Coneheads" in identity.reason


def test_non_music_video_is_dropped(yt, mb):
    identity = identify("PzP8mw7JUzI", yt, mb, history("WPF C# Professional Modern Flat UI Tutorial", "Payload"))
    assert identity.kind == "not_music"
    assert mb.calls == []


def test_substituted_watch_track_goes_to_review(yt, mb):
    identity = identify("XsCPCmpNeto", yt, mb, history("(Sittin' On) The Dock of the Bay", "Tommy Emmanuel"))
    assert identity.kind == "review"
    assert "different video" in identity.reason
    assert identity.song_key == "tommy emmanuel|sittin on the dock of the bay"


def test_music_video_without_album_goes_to_review(yt, mb):
    identity = identify("GLvohMXgcBo", yt, mb, history("Under The Bridge", "Red Hot Chili Peppers"))
    assert identity.kind == "review"
    assert "no album" in identity.reason
    assert BLOOD_SUGAR_SEX_MAGIK in [c.release_group_mbid for c in identity.candidates]


def test_omv_and_atv_resolve_to_same_recording_and_merge(state):
    yt, mb = Recorded("synthetic_editions"), Recorded("synthetic_editions")
    state.add_plays([play("synthOMV", 0, "Song (Official Video)", "Band"), play("synthATV", 1, "Song", "Band - Topic")])
    identify_new(state, yt, mb)
    assert {s.song_key for s in state.songs()} == {"rec-song"}
    assert select(state) == ["rec-song"]


def test_plays_merge_across_video_ids_after_identify(state, yt, mb):
    state.add_plays([play("GLvohMXgcBo", 0, "Under The Bridge"), play("4UnU3r0M3zg", 1, "Under the Bridge")])
    assert identify_new(state, yt, mb) == 2
    keys = {s.song_key for s in state.songs()}
    assert len(keys) == 1
    assert select(state) == list(keys)


def test_once_played_not_liked_not_selected(state, yt, mb):
    state.add_plays([play("H4rBLGmbe80", 0, "Soul to Squeeze")])
    identify_new(state, yt, mb)
    assert select(state) == []


def test_liked_or_playlisted_songs_selected_without_plays(state, yt, mb):
    state.set_liked([LibrarySong("vB8dweYCLes", "I Robot", "I Robot", ["The Alan Parsons Project"])])
    state.add_plays([play("N47SWUcYhQU", 0, "Mammagamma", "The Alan Parsons Project - Topic")])
    state.set_playlists({"Chill Music": ["N47SWUcYhQU"]})
    identify_new(state, yt, mb)
    assert len(select(state)) == 2


def test_not_music_never_selected(state, yt, mb):
    state.add_plays([play("PzP8mw7JUzI", m, "WPF C# Professional Modern Flat UI Tutorial", "Payload") for m in range(3)])
    identify_new(state, yt, mb)
    [song] = state.songs()
    assert song.status == "not_music"
    assert select(state) == []


def test_identify_new_persists_status_review_reason_and_candidates(state, yt, mb):
    state.add_plays([play("H4rBLGmbe80", 0, "Soul to Squeeze"), play("Y2Duog7ZWcA", 1, "Down To The Waterline", "Dire Straits - Topic")])
    identify_new(state, yt, mb)
    statuses = {s.video_id: s.status for s in state.songs()}
    assert statuses == {"H4rBLGmbe80": "review", "Y2Duog7ZWcA": "identified"}
    reason, candidates = state.review_detail("H4rBLGmbe80")
    assert "Coneheads (Music From The Motion Picture Soundtrack)" in reason
    assert candidates[0]["release_group_title"] == "Coneheads: Music From the Motion Picture Soundtrack"
    assert state.review_detail("Y2Duog7ZWcA") is None
    assert identify_new(state, yt, mb) == 0


def test_identify_new_caches_lookups_across_songs(state, yt, mb):
    state.add_plays(
        [
            play("N47SWUcYhQU", 0, "Mammagamma", "The Alan Parsons Project - Topic"),
            play("vB8dweYCLes", 1, "I Robot", "The Alan Parsons Project - Topic"),
        ]
    )
    identify_new(state, yt, mb)
    assert mb.calls.count(lookup_key("search_artists", ("The Alan Parsons Project",))) == 1
    assert mb.calls.count(lookup_key("release_groups", (ALAN_PARSONS_PROJECT,))) == 1


class FakeResponse:
    def __init__(self, payload, status_code=200):
        self.payload = payload
        self.status_code = status_code

    def raise_for_status(self):
        pass

    def json(self):
        return self.payload


class FakeSession:
    def __init__(self, statuses=()):
        self.headers = {}
        self.requests = []
        self.statuses = list(statuses)

    def get(self, url, params=None, timeout=None):
        self.requests.append((url, params))
        return FakeResponse({"artists": []}, self.statuses.pop(0) if self.statuses else 200)


def test_musicbrainz_client_identifies_itself_and_throttles():
    now = [100.0]
    sleeps = []

    def sleep(seconds):
        sleeps.append(seconds)
        now[0] += seconds

    session = FakeSession()
    client = MusicBrainz(session=session, clock=lambda: now[0], sleep=sleep)
    client.search_artists("A")
    now[0] += 0.25
    client.search_artists("B")
    assert session.headers["User-Agent"] == "ytm-migrate/0.1 ( jesse.gollub@gmail.com )"
    assert len(session.requests) == 2
    assert sleeps == [pytest.approx(0.75)]


def test_musicbrainz_client_backs_off_and_retries_on_503():
    now = [0.0]
    sleeps = []

    def sleep(seconds):
        sleeps.append(seconds)
        now[0] += seconds

    session = FakeSession([503, 503])
    assert MusicBrainz(session=session, clock=lambda: now[0], sleep=sleep).search_artists("A") == []
    assert len(session.requests) == 3
    assert sleeps == [2, 4]


def test_release_group_lookup_names_the_first_credited_artist():
    group = {
        "id": "rg",
        "title": "Together",
        "primary-type": "Album",
        "artist-credit": [
            {"name": "Partner (credited)", "joinphrase": " & ", "artist": {"id": "p", "name": "Partner"}},
            {"name": "Solo", "artist": {"id": "s", "name": "Solo Artist"}},
        ],
    }
    session = FakeSession()
    session.get = lambda url, params=None, timeout=None: FakeResponse(group, 200)
    found = MusicBrainz(session=session, clock=lambda: 0.0, sleep=lambda s: None).release_group("rg")
    assert (found["credit"], found["credit-name"], found["credit-artist"]) == (["p", "s"], "Partner (credited) & Solo", "Partner")


def test_musicbrainz_client_rides_out_a_longer_outage():
    now = [0.0]
    sleeps = []

    def sleep(seconds):
        sleeps.append(seconds)
        now[0] += seconds

    session = FakeSession([503] * 6)
    assert MusicBrainz(session=session, clock=lambda: now[0], sleep=sleep).search_artists("A") == []
    assert len(session.requests) == 7
    assert sleeps == [2, 4, 8, 16, 32, 60]
