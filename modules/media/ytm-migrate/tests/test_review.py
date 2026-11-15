from types import SimpleNamespace

from ytm_migrate import review
from ytm_migrate.navidrome import LibraryIndex
from ytm_migrate.state import State

RG = "11111111-1111-1111-1111-111111111111"
RG2 = "22222222-2222-2222-2222-222222222222"
ARTIST = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"


class FakeMB:
    def __init__(self):
        self.groups = {
            RG: {"id": RG, "title": "Dreamland", "primary-type": "Album", "secondary-types": [],
                 "first-release-date": "2020-08-07", "credit": [ARTIST], "credit-name": "Glass Animals",
                 "credit-artist": "Glass Animals"},
            RG2: {"id": RG2, "title": "<b>Other</b>", "primary-type": "Album", "secondary-types": [],
                  "first-release-date": "2019", "credit": ["bbbb", "cccc"], "credit-name": "Someone Else & Friend",
                  "credit-artist": "Someone Else"},
        }

    def release_group(self, mbid):
        return self.groups[mbid]

    def release_group_of_release(self, mbid):
        return RG2

    def search_release_groups(self, artist, album):
        return [self.groups[RG]]


class FakeLidarr:
    def __init__(self, error=None, result="queued"):
        self.calls = []
        self.error = error
        self.result = result

    def queue_album(self, artist_mbid, release_group_mbid):
        self.calls.append((artist_mbid, release_group_mbid))
        if self.error:
            raise self.error
        return self.result


class FakeNavidrome:
    def __init__(self, albums=()):
        self.albums = set(albums)

    def index(self):
        return LibraryIndex(albums=self.albums)


def make(tmp_path, lidarr=None, navidrome=None):
    state = State(tmp_path / "s.db")
    state.set_identity("v1", "k1", None, None, "review", "Glass Animals", "Heat Waves", None)
    state.set_review(
        "v1", "3 releases contain this song",
        [{"artist_mbid": ARTIST, "artist_name": "Glass Animals", "release_group_mbid": RG,
          "release_group_title": "Dreamland", "primary_type": "Album", "secondary_types": [],
          "first_release_date": "2020-08-07", "disambiguation": ""}],
    )
    state.set_identity("v2", "k2", ARTIST, RG, "identified", "X", "Auto", "Y")
    clients = SimpleNamespace(mb=FakeMB(), lidarr=lidarr or FakeLidarr(), navidrome=navidrome or FakeNavidrome())
    return state, clients


def now(job):
    job()


def confirm(state, clients, form, run=now):
    return review.confirm(state, clients, form, run=run, open_state=lambda: state)


def test_index_lists_only_review_items(tmp_path):
    state, _ = make(tmp_path)
    page = review.index(state).body
    assert "Heat Waves" in page
    assert "Auto" not in page
    assert "1 left to review" in page
    assert "1 added automatically" in page
    assert "Dreamland" in page and "3 releases contain this song" in page


def test_confirm_queues_album_once(tmp_path):
    state, clients = make(tmp_path)
    response = confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG})
    assert (response.status, response.location) == (303, "/")
    assert clients.lidarr.calls == [(ARTIST, RG)]
    [song] = [s for s in state.songs() if s.video_id == "v1"]
    assert (song.status, song.artist_mbid, song.release_group_mbid) == ("queued", ARTIST, RG)
    assert state.review_items() == []


def test_pick_accepts_pasted_release_group_url(tmp_path):
    state, clients = make(tmp_path)
    form = {"video_id": "v1", "url": f"https://musicbrainz.org/release-group/{RG}"}
    page = review.pick(state, clients, form).body
    assert "Glass Animals" in page and "Dreamland" in page
    assert clients.lidarr.calls == []
    confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG})
    assert clients.lidarr.calls == [(ARTIST, RG)]


def test_pick_resolves_release_url_and_search(tmp_path):
    state, clients = make(tmp_path)
    form = {"video_id": "v1", "url": "https://musicbrainz.org/release/" + ARTIST}
    assert "Someone Else" in review.pick(state, clients, form).body
    form = {"video_id": "v1", "artist": "glass", "album": "dream"}
    assert "Glass Animals" in review.pick(state, clients, form).body


def test_skip_survives_rerun(tmp_path):
    state, _ = make(tmp_path)
    assert review.skip(state, {"video_id": "v1"}).status == 303
    assert state.review_items() == []
    assert state.songs("new") == []
    assert [s.status for s in state.songs() if s.video_id == "v1"] == ["skipped"]


def test_html_is_escaped(tmp_path):
    state, clients = make(tmp_path)
    state.set_identity("v3", "k3", None, None, "review", "<script>x</script>", "<img src=x>", None)
    page = review.index(state).body
    assert "<script>x</script>" not in page and "<img src=x>" not in page
    form = {"video_id": "v1", "url": f"https://musicbrainz.org/release-group/{RG2}"}
    assert "<b>Other</b>" not in review.pick(state, clients, form).body


def test_lidarr_error_leaves_item_in_review(tmp_path):
    state, clients = make(tmp_path, FakeLidarr(RuntimeError("lidarr <down>")))
    assert confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG}).status == 303
    assert [s.video_id for s in state.review_items()] == ["v1"]
    assert "lidarr &lt;down&gt;" in review.index(state).body
    assert "lidarr" not in review.index(state).body


def test_confirm_skips_album_already_in_navidrome(tmp_path):
    state, clients = make(tmp_path, navidrome=FakeNavidrome({("glass animals", "dreamland")}))
    assert confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG}).status == 303
    assert clients.lidarr.calls == []
    assert "already in your library" in review.index(state).body
    [song] = [s for s in state.songs() if s.video_id == "v1"]
    assert (song.status, song.release_group_mbid) == ("owned", RG)
    assert state.review_items() == []


def test_confirm_marks_album_lidarr_reports_owned(tmp_path):
    state, clients = make(tmp_path, FakeLidarr(result="owned"))
    confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG})
    assert clients.lidarr.calls == [(ARTIST, RG)]
    assert "already in your library" in review.index(state).body
    assert [s.status for s in state.songs() if s.video_id == "v1"] == ["owned"]


def test_confirm_names_lidarr_artist_for_collaborations(tmp_path):
    state, clients = make(tmp_path)
    state.set_review(
        "v1", "credited to a collaboration",
        [{"artist_mbid": ARTIST, "artist_name": "Glass Animals", "release_group_mbid": RG2,
          "release_group_title": "Other", "primary_type": "Album", "secondary_types": [],
          "first_release_date": "2019", "disambiguation": "",
          "credit_name": "Someone Else & Friend", "credit_artist": "Someone Else"}],
    )
    assert "Lidarr will add under: Someone Else" in review.index(state).body
    form = {"video_id": "v1", "url": f"https://musicbrainz.org/release-group/{RG2}"}
    assert "Lidarr will add under: Someone Else" in review.pick(state, clients, form).body
    state.set_review("v1", "x", [{"artist_mbid": ARTIST, "artist_name": "Glass Animals", "release_group_mbid": RG,
                                  "release_group_title": "Dreamland", "credit_name": "Glass Animals", "credit_artist": "Glass Animals"}])
    assert "Lidarr will add under" not in review.index(state).body
    form = {"video_id": "v1", "url": f"https://musicbrainz.org/release-group/{RG}"}
    assert "Lidarr will add under" not in review.pick(state, clients, form).body


def test_confirm_answers_before_lidarr_is_done(tmp_path):
    state, clients = make(tmp_path)
    jobs = []
    response = confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG}, run=jobs.append)
    assert (response.status, response.location) == (303, "/")
    assert clients.lidarr.calls == []
    assert [s.status for s in state.songs() if s.video_id == "v1"] == ["confirming"]
    page = review.index(state).body
    assert "Being queued" in page and "Heat Waves" in page and "http-equiv=refresh" in page
    assert "0 left to review" in page
    jobs[0]()
    assert clients.lidarr.calls == [(ARTIST, RG)]
    assert [s.status for s in state.songs() if s.video_id == "v1"] == ["queued"]
    page = review.index(state).body
    assert "http-equiv=refresh" not in page
    assert "<p class='toast'>Queued Glass Animals — " in page
    assert "Queued Glass Animals" not in review.index(state).body


def test_second_confirm_while_confirming_does_nothing(tmp_path):
    state, clients = make(tmp_path)
    jobs = []
    confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG}, run=jobs.append)
    confirm(state, clients, {"video_id": "v1", "release_group_mbid": RG}, run=jobs.append)
    assert len(jobs) == 1


def test_messages_are_popups_and_index_keeps_scroll(tmp_path):
    state, clients = make(tmp_path)
    state.add_confirm_message("v1", "lidarr down", error=True)
    page = review.index(state).body
    assert "<div class=toasts><p class='toast error'>v1: lidarr down</p></div>" in page
    assert "reviewScroll" in page
    assert "reviewScroll" not in review.pick_form(state, "v1").body


def test_song_and_albums_link_out(tmp_path):
    state, clients = make(tmp_path)
    page = review.index(state).body
    assert "href='https://music.youtube.com/watch?v=v1' target=_blank" in page
    assert "href='https://musicbrainz.org/release-group/" in page


def test_songs_with_same_best_guess_are_grouped_and_confirmed_together(tmp_path):
    state, clients = make(tmp_path)
    state.set_identity("v3", "k3", None, None, "review", "Glass Animals", "Tangerine", None)
    state.set_review("v3", "x", state.review_detail("v1")[1])
    state.set_identity("v4", "k4", None, None, "review", "Muse", "Madness", None)
    page = review.index(state).body
    assert page.count("<section class=group") == 2
    assert "Confirm album for all 2" in page
    assert f"coverartarchive.org/release-group/{RG}/front-250" in page
    assert "no album guess" in page and "id=filter" in page and "id=sort" in page
    confirm(state, clients, {"video_id": "v1,v3", "release_group_mbid": RG})
    assert clients.lidarr.calls == [(ARTIST, RG)]
    assert [s.video_id for s in state.review_items()] == ["v4"]
    assert {s.video_id for s in state.songs("queued")} == {"v1", "v3"}
