import pytest

from ytm_migrate.lidarr import REFRESH_ATTEMPTS, AlbumNotFoundError, Lidarr, LidarrConfigError, LidarrRefreshError

ARTIST = "artist-mbid"
ALBUM = "album-mbid"
ROOT = "/music"


class Response:
    def __init__(self, body):
        self.body = body

    def raise_for_status(self):
        pass

    def json(self):
        return self.body


class FakeSession:
    def __init__(
        self, artists=(), albums=(), after_refresh=None, root_folders=None, quality=None, metadata=None, statuses=("started", "completed"), scans=()
    ):
        self.headers = {}
        self.calls = []
        self.artists = list(artists)
        self.albums = list(albums)
        self.after_refresh = after_refresh
        self.statuses = list(statuses)
        self.polled = 0
        self.scans = list(scans)
        self.lookup = [{"foreignArtistId": "decoy", "artistName": "Nope"}, {"foreignArtistId": ARTIST, "artistName": "The Band", "images": []}]
        self.lists = {
            "/api/v1/rootfolder": [{"id": 1, "path": ROOT}] if root_folders is None else root_folders,
            "/api/v1/qualityprofile": [{"id": 2, "name": "YouTube"}] if quality is None else quality,
            "/api/v1/metadataprofile": [{"id": 3, "name": "Everything"}] if metadata is None else metadata,
        }

    def request(self, method, url, **kwargs):
        path = url.removeprefix("http://lidarr")
        self.calls.append((method, path, kwargs.get("params"), kwargs.get("json")))
        if method == "GET" and path in self.lists:
            return Response(self.lists[path])
        if (method, path) == ("GET", "/api/v1/artist"):
            return Response(self.artists)
        if (method, path) == ("GET", "/api/v1/artist/lookup"):
            return Response(self.lookup)
        if (method, path) == ("POST", "/api/v1/artist"):
            self.artists = [{"id": 10, "foreignArtistId": ARTIST}]
            return Response(self.artists[0])
        if (method, path) == ("GET", "/api/v1/album"):
            return Response(self.albums)
        if (method, path) == ("POST", "/api/v1/command"):
            return Response({"id": 77, "name": kwargs["json"]["name"], "status": "queued"})
        if (method, path) == ("GET", "/api/v1/command"):
            name, status = self.scans.pop(0) if self.scans else ("RescanFolders", "completed")
            return Response([{"id": 5, "name": name, "status": status}, {"id": 6, "name": "AlbumSearch", "status": "started"}])
        if (method, path) == ("GET", "/api/v1/command/77"):
            status = self.statuses[min(self.polled, len(self.statuses) - 1)]
            self.polled += 1
            if status == "completed" and self.after_refresh:
                self.albums = self.after_refresh
            return Response({"id": 77, "status": status})
        return Response({})

    def sent(self, method, path):
        return [json for m, p, _, json in self.calls if (m, p) == (method, path)]


def client(session, sleeps=None):
    return Lidarr(
        "http://lidarr",
        "key",
        session=session,
        root_folder=ROOT,
        quality_profile="YouTube",
        metadata_profile="Everything",
        sleep=(sleeps if sleeps is not None else []).append,
    )


def album(monitored=False, files=0):
    return {"id": 55, "foreignAlbumId": ALBUM, "monitored": monitored, "statistics": {"trackFileCount": files}}


def test_new_artist_added_without_monitoring_everything():
    session = FakeSession(after_refresh=[album()])
    client(session).queue_album(ARTIST, ALBUM)
    [body] = session.sent("POST", "/api/v1/artist")
    assert body["foreignArtistId"] == ARTIST
    assert body["artistName"] == "The Band"
    assert ("GET", "/api/v1/artist/lookup", {"term": f"lidarr:{ARTIST}"}, None) in session.calls
    assert body["monitored"] is True
    assert body["monitorNewItems"] == "none"
    assert body["addOptions"] == {"monitor": "none", "searchForMissingAlbums": False}
    assert (body["rootFolderPath"], body["qualityProfileId"], body["metadataProfileId"]) == (ROOT, 2, 3)
    assert session.headers["X-Api-Key"] == "key"


def test_only_target_album_monitored_and_searched():
    session = FakeSession(artists=[{"id": 10}], albums=[album(), {"id": 56, "foreignAlbumId": "other", "monitored": False}])
    assert client(session).queue_album(ARTIST, ALBUM) == "queued"
    assert session.sent("POST", "/api/v1/artist") == []
    assert session.sent("PUT", "/api/v1/album/monitor") == [{"albumIds": [55], "monitored": True}]
    assert session.sent("POST", "/api/v1/command") == [{"name": "AlbumSearch", "albumIds": [55]}]


def test_already_monitored_album_is_noop():
    session = FakeSession(artists=[{"id": 10, "monitored": True}], albums=[album(monitored=True)])
    assert client(session).queue_album(ARTIST, ALBUM) == "already"
    assert session.sent("PUT", "/api/v1/album/monitor") == []
    assert session.sent("POST", "/api/v1/command") == []


def test_refreshes_artist_until_album_appears():
    session = FakeSession(after_refresh=[album()])
    sleeps = []
    assert client(session, sleeps).queue_album(ARTIST, ALBUM) == "queued"
    assert session.sent("POST", "/api/v1/command")[0] == {"name": "RefreshArtist", "artistId": 10}
    assert session.sent("POST", "/api/v1/command")[-1] == {"name": "AlbumSearch", "albumIds": [55]}


def test_missing_album_raises_after_bounded_polling():
    session = FakeSession()
    sleeps = []
    with pytest.raises(AlbumNotFoundError, match=ALBUM):
        client(session, sleeps).queue_album(ARTIST, ALBUM)
    assert 0 < len(sleeps) <= REFRESH_ATTEMPTS
    assert session.sent("PUT", "/api/v1/album/monitor") == []


def test_new_artist_waits_for_refresh_before_reading_albums():
    session = FakeSession(albums=[album()], after_refresh=[album(files=3)], statuses=("queued", "started", "started", "completed"))
    sleeps = []
    assert client(session, sleeps).queue_album(ARTIST, ALBUM) == "owned"
    assert session.polled == 4
    assert len(sleeps) == 4


@pytest.mark.parametrize("busy", ["RescanFolders", "RefreshArtist", "BulkRefreshArtist"])
def test_waits_for_lidarrs_own_refresh_and_rescan(busy):
    session = FakeSession(after_refresh=[album(files=1)], scans=((busy, "queued"), (busy, "started")))
    sleeps = []
    assert client(session, sleeps).queue_album(ARTIST, ALBUM) == "owned"
    assert len(sleeps) == 4
    assert session.scans == []


def test_owned_album_is_never_monitored_or_searched():
    session = FakeSession(artists=[{"id": 10}], albums=[album(files=1)])
    assert client(session).queue_album(ARTIST, ALBUM) == "owned"
    assert session.sent("PUT", "/api/v1/album/monitor") == []
    assert session.sent("POST", "/api/v1/command") == []


def test_owned_album_of_new_artist_is_not_monitored():
    session = FakeSession(after_refresh=[album(files=2)])
    assert client(session).queue_album(ARTIST, ALBUM) == "owned"
    assert session.sent("PUT", "/api/v1/album/monitor") == []
    assert session.sent("POST", "/api/v1/command") == [{"name": "RefreshArtist", "artistId": 10}]


def test_failed_refresh_raises_without_queueing():
    session = FakeSession(after_refresh=[album()], statuses=("started", "failed"))
    with pytest.raises(LidarrRefreshError, match="failed"):
        client(session).queue_album(ARTIST, ALBUM)
    assert session.sent("PUT", "/api/v1/album/monitor") == []


def test_refresh_that_never_finishes_raises_after_bounded_polling():
    session = FakeSession(after_refresh=[album()], statuses=("started",))
    sleeps = []
    with pytest.raises(LidarrRefreshError):
        client(session, sleeps).queue_album(ARTIST, ALBUM)
    assert len(sleeps) == REFRESH_ATTEMPTS
    assert session.sent("PUT", "/api/v1/album/monitor") == []


@pytest.mark.parametrize(
    "missing, kwargs",
    [
        ("YouTube", {"quality": []}),
        ("Everything", {"metadata": []}),
        (ROOT, {"root_folders": []}),
    ],
)
def test_missing_root_folder_or_profile_is_named(missing, kwargs):
    with pytest.raises(LidarrConfigError, match=missing):
        client(FakeSession(**kwargs)).queue_album(ARTIST, ALBUM)


def test_unknown_artist_lookup_raises():
    session = FakeSession()
    session.lookup = []
    with pytest.raises(LidarrConfigError, match=ARTIST):
        client(session).queue_album(ARTIST, ALBUM)


def test_root_folder_trailing_slash_ignored():
    session = FakeSession(after_refresh=[album()], root_folders=[{"id": 1, "path": ROOT + "/"}])
    assert client(session).queue_album(ARTIST, ALBUM) == "queued"


def test_unmonitored_existing_artist_is_monitored_without_new_items():
    existing = {"id": 10, "artistName": "Muse", "monitored": False, "monitorNewItems": "all", "path": "/music/Muse"}
    session = FakeSession(artists=[existing], albums=[album()])
    assert client(session).queue_album(ARTIST, ALBUM) == "queued"
    [body] = session.sent("PUT", "/api/v1/artist/10")
    assert (body["monitored"], body["monitorNewItems"], body["path"]) == (True, "none", "/music/Muse")


def test_monitored_artist_is_left_alone():
    session = FakeSession(artists=[{"id": 10, "monitored": True, "monitorNewItems": "none"}], albums=[album()])
    client(session).queue_album(ARTIST, ALBUM)
    assert session.sent("PUT", "/api/v1/artist/10") == []


def test_monitored_album_of_unmonitored_artist_gets_artist_fixed_and_searched():
    session = FakeSession(artists=[{"id": 10, "monitored": False}], albums=[album(monitored=True)])
    assert client(session).queue_album(ARTIST, ALBUM) == "already"
    assert session.sent("PUT", "/api/v1/artist/10")[0]["monitored"] is True
    assert session.sent("POST", "/api/v1/command") == [{"name": "AlbumSearch", "albumIds": [55]}]


def test_owned_album_never_touches_the_artist():
    session = FakeSession(artists=[{"id": 10, "monitored": False}], albums=[album(files=3)])
    assert client(session).queue_album(ARTIST, ALBUM) == "owned"
    assert session.sent("PUT", "/api/v1/artist/10") == []
