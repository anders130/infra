import pytest
import requests

import provision

ROOT = "/mnt/rackflix/data/Music"

QUALITY_SCHEMA = {
    "name": "",
    "upgradeAllowed": False,
    "cutoff": 0,
    "items": [
        {"quality": {"id": 0, "name": "Unknown"}, "items": [], "allowed": False},
        {
            "id": 1004,
            "name": "High Quality Lossy",
            "items": [{"quality": {"id": 12, "name": "AAC-VBR"}, "items": [], "allowed": False}],
            "allowed": False,
        },
        {
            "id": 1005,
            "name": "Lossless",
            "items": [{"quality": {"id": 6, "name": "FLAC"}, "items": [], "allowed": False}],
            "allowed": False,
        },
    ],
}

INDEXER_SCHEMA = [
    {
        "implementation": "YouTubeIndexer",
        "configContract": "YouTubeIndexerSettings",
        "enableRss": False,
        "fields": [{"name": "cookiePath", "value": ""}, {"name": "earlyReleaseLimit", "value": None}],
    }
]

CLIENT_SCHEMA = [
    {
        "implementation": "YoutubeClient",
        "configContract": "YoutubeProviderSettings",
        "fields": [{"name": "downloadPath", "value": ""}, {"name": "reEncode", "value": 1}],
    }
]

DESIRED = {
    "rootFolder": {
        "name": "Music",
        "path": ROOT,
    },
    "metadataProfile": "Everything",
    "mediaManagement": {"recycleBin": "/data/recycle", "recycleBinCleanupDays": 30},
    "qualityProfile": {"name": "YouTube", "allowed": ["Unknown", "High Quality Lossy"]},
    "naming": {
        "artistFolderFormat": "{Artist Name}",
        "standardTrackFormat": "{Album Title}/{track:00} {Track Title}",
        "multiDiscTrackFormat": "{Album Title}/{medium:0}-{track:00} {Track Title}",
    },
    "metadataProvider": {"embedCoverArt": True},
    "indexers": [
        {"name": "YouTube", "implementation": "YouTubeIndexer", "fields": {"cookiePath": "/data/cookies.txt"}}
    ],
    "downloadClients": [
        {"name": "YouTube", "implementation": "YoutubeClient", "fields": {"downloadPath": "/data/dl"}}
    ],
}


def types(key, inner, names, allowed=False):
    return [{inner: {"id": i, "name": n}, "allowed": allowed} for i, n in enumerate(names)]


METADATA_SCHEMA = {
    "primaryAlbumTypes": types("primaryAlbumTypes", "albumType", ["Album", "EP", "Single"]),
    "secondaryAlbumTypes": types("secondaryAlbumTypes", "albumType", ["Studio", "Compilation", "Live"]),
    "releaseStatuses": types("releaseStatuses", "releaseStatus", ["Official", "Bootleg"]),
}


class Response:
    ok = True
    status_code = 200
    text = ""

    def __init__(self, body):
        self.body = body

    def json(self):
        return self.body


class FakeSession:
    def __init__(self, **state):
        self.state = {
            "rootfolder": [],
            "qualityprofile": [],
            "metadataprofile": [{"id": 7, "name": "Standard"}],
            "indexer": [],
            "downloadclient": [],
            "config/naming": {"id": 1, "renameTracks": True, "standardTrackFormat": "old"},
            "config/metadataProvider": {"id": 1, "writeAudioTags": "no", "scrubAudioTags": True},
            "config/mediamanagement": {"id": 1, "recycleBin": "", "recycleBinCleanupDays": 7},
            "metadataprofile/schema": METADATA_SCHEMA,
            "qualityprofile/schema": QUALITY_SCHEMA,
            "indexer/schema": INDEXER_SCHEMA,
            "downloadclient/schema": CLIENT_SCHEMA,
            **state,
        }
        self.calls = []
        self.next_id = 100

    def request(self, method, url, json=None, params=None, **kwargs):
        path = url.split("/api/v1/", 1)[1]
        self.calls.append((method, path, json, params))
        if method == "GET":
            return Response(self.state[path])
        if method == "POST":
            body = {**json, "id": self.next_id}
            self.next_id += 1
            self.state[path].append(body)
            return Response(body)
        if method == "PUT":
            collection, _, item_id = path.rpartition("/")
            if isinstance(self.state.get(collection), list):
                items = self.state[collection]
                self.state[collection] = [json if i["id"] == int(item_id) else i for i in items]
            else:
                self.state[collection] = json
            return Response(json)
        raise AssertionError(method)

    def writes(self, method, prefix):
        return [c for c in self.calls if c[0] == method and c[1].startswith(prefix)]


@pytest.fixture
def cookies(tmp_path):
    path = tmp_path / "cookies.txt"
    path.write_text("x")
    return path


def run(session, tmp):
    return provision.provision(session, "http://lidarr", {**DESIRED, "cookiesPath": str(tmp)})


def allowed(profile):
    return {
        key: {entry[inner]["name"]: entry["allowed"] for entry in profile[key]}
        for key, inner in [("primaryAlbumTypes", "albumType"), ("secondaryAlbumTypes", "albumType"), ("releaseStatuses", "releaseStatus")]
    }


def test_creates_root_folder_when_missing(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    posts = session.writes("POST", "rootfolder")
    assert len(posts) == 1
    assert posts[0][2]["path"] == ROOT
    [profile] = session.writes("POST", "metadataprofile")
    assert posts[0][2]["defaultMetadataProfileId"] == session.state["metadataprofile"][-1]["id"]
    assert session.state["metadataprofile"][-1]["name"] == "Everything"


def test_root_folder_never_monitors_by_default(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    body = session.writes("POST", "rootfolder")[0][2]
    assert (body["defaultMonitorOption"], body["defaultNewItemMonitorOption"]) == ("none", "none")


def test_root_folder_present_and_matching_is_noop(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    session.calls.clear()
    run(session, tmp=cookies)
    assert session.writes("POST", "rootfolder") == []
    assert session.writes("PUT", "rootfolder") == []


def test_existing_root_folder_is_corrected(cookies):
    stale = {
        "id": 3,
        "name": "Music",
        "path": ROOT + "/",
        "defaultQualityProfileId": 1,
        "defaultMetadataProfileId": 7,
        "defaultMonitorOption": "all",
        "defaultNewItemMonitorOption": "all",
        "defaultTags": [],
    }
    session = FakeSession(rootfolder=[stale])
    run(session, tmp=cookies)
    assert session.writes("POST", "rootfolder") == []
    [put] = session.writes("PUT", "rootfolder/3")
    body = put[2]
    assert body["path"] == ROOT + "/"
    assert (body["defaultMonitorOption"], body["defaultNewItemMonitorOption"]) == ("none", "none")
    assert body["defaultMetadataProfileId"] != 7


def test_metadata_profile_allows_everything(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    [post] = session.writes("POST", "metadataprofile")
    assert post[2]["name"] == "Everything"
    assert all(all(v.values()) for v in allowed(post[2]).values())
    assert allowed(post[2])["secondaryAlbumTypes"].keys() == {"Studio", "Compilation", "Live"}


def test_existing_metadata_profile_is_opened_up(cookies):
    existing = {"id": 9, "name": "Everything", **{**METADATA_SCHEMA, "releaseStatuses": types("releaseStatuses", "releaseStatus", ["Official", "Bootleg"], True)}}
    session = FakeSession(metadataprofile=[{"id": 7, "name": "Standard"}, existing])
    run(session, tmp=cookies)
    assert session.writes("POST", "metadataprofile") == []
    [put] = session.writes("PUT", "metadataprofile/9")
    assert all(all(v.values()) for v in allowed(put[2]).values())
    assert session.writes("POST", "rootfolder")[0][2]["defaultMetadataProfileId"] == 9


def test_naming_renames_new_imports(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    puts = session.writes("PUT", "config/naming")
    assert len(puts) == 1
    assert puts[0][2]["renameTracks"] is True


def test_recycle_bin_configured(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    [put] = session.writes("PUT", "config/mediamanagement")
    assert put[1] == "config/mediamanagement/1"
    assert (put[2]["recycleBin"], put[2]["recycleBinCleanupDays"]) == ("/data/recycle", 30)


def test_naming_formats_put_verbatim(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    body = session.writes("PUT", "config/naming")[0][2]
    for key, value in DESIRED["naming"].items():
        assert body[key] == value


def test_tags_written_for_new_files_only(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    body = session.writes("PUT", "config/metadataProvider")[0][2]
    assert body["writeAudioTags"] == "newFiles"
    assert body["scrubAudioTags"] is False


def test_indexer_and_client_created_when_missing(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    indexer = session.writes("POST", "indexer")[0][2]
    assert indexer["name"] == "YouTube"
    assert indexer["implementation"] == "YouTubeIndexer"
    assert {"name": "cookiePath", "value": "/data/cookies.txt"} in indexer["fields"]
    client = session.writes("POST", "downloadclient")[0][2]
    assert client["implementation"] == "YoutubeClient"
    assert {"name": "downloadPath", "value": "/data/dl"} in client["fields"]


def test_indexer_and_client_upserted_by_name(cookies):
    session = FakeSession(
        indexer=[{"id": 11, "name": "YouTube", "implementation": "YouTubeIndexer", "fields": []}],
        downloadclient=[{"id": 12, "name": "YouTube", "implementation": "YoutubeClient", "fields": []}],
    )
    run(session, tmp=cookies)
    assert session.writes("POST", "indexer") == []
    assert session.writes("POST", "downloadclient") == []
    assert session.writes("PUT", "indexer/11")[0][3] == {"forceSave": "true"}
    assert session.writes("PUT", "downloadclient/12")


def test_quality_profile_allows_listed_items_only(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    profile = session.writes("POST", "qualityprofile")[0][2]
    assert profile["name"] == "YouTube"
    assert profile["upgradeAllowed"] is False
    allowed = {i.get("name") or i["quality"]["name"]: i["allowed"] for i in profile["items"]}
    assert allowed == {"Unknown": True, "High Quality Lossy": True, "Lossless": False}
    assert profile["cutoff"] in (0, 1004)


def test_second_run_makes_no_writes(cookies):
    session = FakeSession()
    run(session, tmp=cookies)
    session.calls.clear()
    changes = run(session, tmp=cookies)
    assert [c for c in session.calls if c[0] != "GET"] == []
    assert changes == 0


class RejectingSession(FakeSession):
    def request(self, method, url, **kwargs):
        if method == "POST" and url.endswith("/indexer"):
            return RejectingResponse(None)
        return super().request(method, url, **kwargs)


class RejectingResponse(Response):
    ok = False
    status_code = 400
    text = "Folder '/music' is not writable by user 'lidarr'"


def test_missing_cookies_skips_indexer_and_client(tmp_path, capsys):
    session = FakeSession()
    run(session, tmp=tmp_path / "absent.txt")
    assert [c for c in session.calls if "indexer" in c[1] or "downloadclient" in c[1]] == []
    assert session.writes("POST", "rootfolder")
    assert "no cookies file" in capsys.readouterr().out


def test_rejected_provider_with_cookies_present_raises(cookies):

    with pytest.raises(requests.HTTPError):
        run(RejectingSession(), tmp=cookies)


def test_unknown_implementation_exits_clearly(cookies):

    session = FakeSession(**{"indexer/schema": []})
    with pytest.raises(SystemExit, match="YouTubeIndexer"):
        run(session, tmp=cookies)


def test_http_error_carries_lidarr_message(tmp_path):
    cookies = tmp_path / "cookies.txt"
    cookies.write_text("x")
    with pytest.raises(requests.HTTPError, match="HTTP 400: Folder '/music' is not writable"):
        run(RejectingSession(), tmp=cookies)
