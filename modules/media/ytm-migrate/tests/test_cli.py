import pytest

from ytm_migrate import cli
from ytm_migrate.listenbrainz import ListenBrainzError, SubmitResult
from ytm_migrate.navidrome import ApplyReport, LibraryIndex, ListenBrainzLinkedError
from ytm_migrate.state import State

ALLOWLIST = {"Chill Music", "Favorites"}

IDENTITIES = {
    "n50LrYEcqo4": ("artist-1", "rg-1", "Artist One", "Echoes"),
    "vB8dweYCLes": ("artist-2", "rg-2", "Artist Two", "I Robot"),
}
FAILING = "XsCPCmpNeto"


def fake_identify(state, song, yt, mb, liked):
    if song.video_id == FAILING:
        raise RuntimeError("lookup failed")
    if song.video_id in IDENTITIES:
        artist_mbid, rg_mbid, artist, album = IDENTITIES[song.video_id]
        state.set_identity(
            song.video_id, f"{artist}|{song.video_id}", artist_mbid, rg_mbid, "identified", artist, song.title, album
        )
    else:
        state.set_identity(song.video_id, None, None, None, "review")


class FakeLidarr:
    def __init__(self, owned=()):
        self.queued = []
        self.owned = set(owned)

    def queue_album(self, artist_mbid, release_group_mbid):
        self.queued.append((artist_mbid, release_group_mbid))
        return "owned" if release_group_mbid in self.owned else "queued"


class FakeNavidrome:
    def __init__(self, linked=False):
        self.linked = linked
        self.applied = 0
        self.checked = 0

    def check_listenbrainz(self):
        self.checked += 1
        if self.linked:
            raise ListenBrainzLinkedError("linked")

    def index(self):
        return LibraryIndex(albums={("artist two", "i robot")})

    def apply(self, state, index):
        if self.linked:
            raise ListenBrainzLinkedError("linked")
        self.applied += 1
        return ApplyReport(1, 2, 3, 4, 5)


class LBResponse:
    def __init__(self, status_code, body):
        self.status_code = status_code
        self.body = body

    def json(self):
        return self.body


class LBSession:
    def __init__(self, valid=True):
        self.valid = valid
        self.gets = []

    def get(self, url, headers=None, timeout=None):
        self.gets.append((url, headers))
        return LBResponse(200, {"code": 200, "valid": self.valid, "user_name": "jesse" if self.valid else None})


@pytest.fixture
def world(monkeypatch):
    submitted = []

    def submit(state, token, session):
        submitted.append(token)
        if token == "broken":
            raise ListenBrainzError("ListenBrainz returned HTTP 500")
        return SubmitResult(7, 2)

    monkeypatch.setattr(cli, "identify_song", fake_identify)
    monkeypatch.setattr(cli, "submit_pending", submit)
    return submitted


def clients(navidrome=None, lidarr=None, lb_session=None, lb_token="tok"):
    return cli.Clients(
        yt=None,
        mb=None,
        lidarr=lidarr or FakeLidarr(),
        navidrome=navidrome or FakeNavidrome(),
        lb_session=lb_session or LBSession(),
        lb_token=lb_token,
    )


def test_dry_run_writes_nothing_remote(tmp_path, takeout_zip, world, capsys):
    c = clients()
    state = State(tmp_path / "state.db")
    assert cli.run(takeout_zip, True, state, c, ALLOWLIST) == 1
    assert c.lidarr.queued == []
    assert c.navidrome.applied == 0
    assert world == []
    out = capsys.readouterr().out
    assert "would queue" in out and "artist-1" in out


def test_summary_counts(tmp_path, takeout_zip, world, capsys):
    c = clients()
    state = State(tmp_path / "state.db")
    assert cli.run(takeout_zip, False, state, c, ALLOWLIST) == 1
    assert c.lidarr.queued == [("artist-1", "rg-1")]
    statuses = {s.video_id: s.status for s in state.songs()}
    assert statuses["n50LrYEcqo4"] == "queued"
    assert statuses["vB8dweYCLes"] == "owned"
    out = capsys.readouterr().out
    for expected in ["queued albums: 1", "owned albums: 1", "errors: 1", "listenbrainz sent: 7", "listenbrainz skipped: 2", "navidrome scrobbles: 4", "navidrome pending: 5"]:
        assert expected in out
    assert "review: " in out and "review: 0" not in out


def test_song_error_does_not_abort_and_is_retried(tmp_path, takeout_zip, world):
    c = clients()
    state = State(tmp_path / "state.db")
    cli.run(takeout_zip, False, state, c, ALLOWLIST)
    assert {s.video_id: s.status for s in state.songs()}[FAILING] == "new"
    assert c.navidrome.applied == 1


def test_listenbrainz_linked(tmp_path, takeout_zip, world, capsys):
    c = clients(FakeNavidrome(linked=True))
    state = State(tmp_path / "state.db")
    assert cli.run(takeout_zip, False, state, c, ALLOWLIST) == 1
    assert world == ["tok"]
    assert c.lidarr.queued == [("artist-1", "rg-1")]
    assert "unlink ListenBrainz" in capsys.readouterr().out


@pytest.fixture
def no_failures(monkeypatch):
    def identify_ok(state, song, yt, mb, liked):
        if song.video_id == FAILING:
            state.set_identity(song.video_id, None, None, None, "review")
        else:
            fake_identify(state, song, yt, mb, liked)

    monkeypatch.setattr(cli, "identify_song", identify_ok)


def test_clean_run_exits_zero(tmp_path, takeout_zip, world, no_failures):
    assert cli.run(takeout_zip, False, State(tmp_path / "state.db"), clients(), ALLOWLIST) == 0


def test_lidarr_owned_album_is_marked_owned(tmp_path, takeout_zip, world, capsys):
    c = clients(lidarr=FakeLidarr(owned={"rg-1"}))
    state = State(tmp_path / "state.db")
    cli.run(takeout_zip, False, state, c, ALLOWLIST)
    assert {s.video_id: s.status for s in state.songs()}["n50LrYEcqo4"] == "owned"
    out = capsys.readouterr().out
    assert "queued albums: 0" in out and "owned albums: 2" in out


def test_dry_run_checks_listenbrainz_token_and_navidrome_link(tmp_path, takeout_zip, world, no_failures, capsys):
    session = LBSession()
    c = clients(lb_session=session)
    assert cli.run(takeout_zip, True, State(tmp_path / "state.db"), c, ALLOWLIST) == 0
    assert session.gets == [("https://api.listenbrainz.org/1/validate-token", {"Authorization": "Token tok"})]
    assert c.navidrome.checked == 1
    out = capsys.readouterr().out
    assert "listenbrainz token: valid (jesse)" in out
    assert "navidrome listenbrainz link: not linked" in out
    assert world == []


def test_dry_run_reports_bad_token_and_linked_navidrome(tmp_path, takeout_zip, world, no_failures, capsys):
    c = clients(navidrome=FakeNavidrome(linked=True), lb_session=LBSession(valid=False))
    assert cli.run(takeout_zip, True, State(tmp_path / "state.db"), c, ALLOWLIST) == 1
    out = capsys.readouterr().out
    assert "listenbrainz token: invalid" in out
    assert "unlink ListenBrainz" in out


def test_listenbrainz_failure_still_runs_navidrome_and_summary(tmp_path, takeout_zip, world, no_failures, capsys):
    c = clients(lb_token="broken")
    assert cli.run(takeout_zip, False, State(tmp_path / "state.db"), c, ALLOWLIST) == 1
    assert c.navidrome.applied == 1
    captured = capsys.readouterr()
    assert "listenbrainz step failed: ListenBrainz returned HTTP 500" in captured.err
    assert "navidrome scrobbles: 4" in captured.out


def test_unreadable_takeout_explains_where_to_put_it(tmp_path, capsys):
    missing = tmp_path / "takeout.zip"
    assert cli.run(missing, False, State(tmp_path / "state.db"), clients(), ALLOWLIST) == 2
    err = capsys.readouterr().err
    assert str(missing) in err and "/var/lib/ytm-migrate" in err
    missing.write_text("not a zip")
    assert cli.run(missing, False, State(tmp_path / "state.db"), clients(), ALLOWLIST) == 2
