from datetime import datetime, timedelta, timezone

import pytest

from ytm_migrate.listenbrainz import ListenBrainzError, SubmitResult, submit_pending
from ytm_migrate.state import State
from ytm_migrate.takeout import Play

START = datetime(2024, 1, 1, tzinfo=timezone.utc)


class Response:
    def __init__(self, status_code=200, headers=None):
        self.status_code = status_code
        self.headers = headers or {}


class FakeSession:
    def __init__(self, *responses):
        self.responses = list(responses)
        self.posts = []

    def post(self, url, **kwargs):
        self.posts.append((url, kwargs))
        return self.responses.pop(0) if self.responses else Response()


def state_with(tmp_path, plays):
    state = State(tmp_path / "state.db")
    state.add_plays(plays)
    return state


def play(n, title="Song", channel="Artist", video_id=None):
    return Play(video_id or f"v{n}", START + timedelta(seconds=n), title, channel)


def test_batches_of_1000(tmp_path):
    state = state_with(tmp_path, [play(n) for n in range(2500)])
    session = FakeSession()
    assert submit_pending(state, "tok", session, sleep=lambda s: None) == SubmitResult(2500, 0)
    sizes = [len(kw["json"]["payload"]) for _, kw in session.posts]
    assert sizes == [1000, 1000, 500]
    url, kw = session.posts[0]
    assert url == "https://api.listenbrainz.org/1/submit-listens"
    assert kw["headers"]["Authorization"] == "Token tok"
    assert kw["json"]["listen_type"] == "import"
    assert kw["json"]["payload"][0]["listened_at"] == int(START.timestamp())


def test_second_call_sends_nothing(tmp_path):
    state = state_with(tmp_path, [play(1), play(2)])
    submit_pending(state, "tok", FakeSession(), sleep=lambda s: None)
    session = FakeSession()
    assert submit_pending(state, "tok", session, sleep=lambda s: None) == SubmitResult(0, 0)
    assert session.posts == []


def test_unsent_after_http_error_are_retried_next_run(tmp_path):
    state = state_with(tmp_path, [play(n) for n in range(1500)])
    session = FakeSession(Response(200), Response(500))
    with pytest.raises(ListenBrainzError):
        submit_pending(state, "tok", session, sleep=lambda s: None)
    assert len(state.pending_listens("listenbrainz")) == 500
    retry = FakeSession()
    assert submit_pending(state, "tok", retry, sleep=lambda s: None) == SubmitResult(500, 0)
    assert state.pending_listens("listenbrainz") == []


def test_rate_limit_sleeps_then_retries_same_batch(tmp_path):
    state = state_with(tmp_path, [play(1)])
    session = FakeSession(Response(429, {"X-RateLimit-Reset-In": "7"}), Response(200))
    sleeps = []
    assert submit_pending(state, "tok", session, sleep=sleeps.append) == SubmitResult(1, 0)
    assert sleeps == [7]
    assert session.posts[0][1]["json"] == session.posts[1][1]["json"]


def test_topic_suffix_stripped_for_unidentified(tmp_path):
    state = state_with(tmp_path, [play(1, "Raw Title", "Some Band - Topic")])
    session = FakeSession()
    submit_pending(state, "tok", session, sleep=lambda s: None)
    meta = session.posts[0][1]["json"]["payload"][0]["track_metadata"]
    assert meta == {"artist_name": "Some Band", "track_name": "Raw Title"}


def test_identified_names_and_album_used(tmp_path):
    state = state_with(tmp_path, [play(1, "Raw Title", "Chan")])
    state.set_identity("v1", "k", "a", "r", "identified", "Real Artist", "Real Title", "Real Album")
    session = FakeSession()
    submit_pending(state, "tok", session, sleep=lambda s: None)
    meta = session.posts[0][1]["json"]["payload"][0]["track_metadata"]
    assert meta == {"artist_name": "Real Artist", "track_name": "Real Title", "release_name": "Real Album"}


def test_rate_limit_retries_are_capped(tmp_path):
    state = state_with(tmp_path, [play(1)])
    session = FakeSession(*[Response(429, {"X-RateLimit-Reset-In": "1"}) for _ in range(10)])
    sleeps = []
    with pytest.raises(ListenBrainzError, match="429"):
        submit_pending(state, "tok", session, sleep=sleeps.append)
    assert len(session.posts) == 6
    assert len(sleeps) == 5
    assert len(state.pending_listens("listenbrainz")) == 1


def test_non_numeric_reset_header_falls_back(tmp_path):
    state = state_with(tmp_path, [play(1)])
    session = FakeSession(Response(429, {"X-RateLimit-Reset-In": "soon"}), Response(200))
    sleeps = []
    submit_pending(state, "tok", session, sleep=sleeps.append)
    assert sleeps == [10]


def test_error_includes_status_and_body(tmp_path):
    state = state_with(tmp_path, [play(1)])
    bad = Response(400)
    bad.text = "bad payload"
    with pytest.raises(ListenBrainzError, match="400.*bad payload"):
        submit_pending(state, "tok", FakeSession(bad), sleep=lambda s: None)


def test_plays_without_artist_or_track_are_skipped_and_not_retried(tmp_path):
    state = state_with(tmp_path, [play(1), play(2, "Orphan", " - Topic"), play(3, "", "Band"), play(4)])
    session = FakeSession()
    assert submit_pending(state, "tok", session, sleep=lambda s: None) == SubmitResult(2, 2)
    assert len(session.posts[0][1]["json"]["payload"]) == 2
    again = FakeSession()
    assert submit_pending(state, "tok", again, sleep=lambda s: None) == SubmitResult(0, 0)
    assert again.posts == []


def test_huge_reset_header_falls_back(tmp_path):
    state = state_with(tmp_path, [play(1)])
    session = FakeSession(Response(429, {"X-RateLimit-Reset-In": "1e400"}), Response(200))
    sleeps = []
    submit_pending(state, "tok", session, sleep=sleeps.append)
    assert sleeps == [10]
