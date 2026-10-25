import time
from typing import Any, Callable, Literal

import requests

REFRESH_ATTEMPTS = 100
REFRESH_WAIT = 3.0
PENDING = ("queued", "started")
LIBRARY_COMMANDS = ("RefreshArtist", "BulkRefreshArtist", "RescanFolders")


class LidarrConfigError(Exception):
    pass


class AlbumNotFoundError(Exception):
    pass


class LidarrRefreshError(Exception):
    pass


class Lidarr:
    def __init__(
        self,
        base_url: str,
        api_key: str,
        root_folder: str,
        quality_profile: str,
        metadata_profile: str,
        session: Any = None,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.base_url = base_url.rstrip("/")
        self.session = session or requests.Session()
        self.session.headers["X-Api-Key"] = api_key
        self.root_folder = root_folder
        self.quality_profile = quality_profile
        self.metadata_profile = metadata_profile
        self.sleep = sleep

    def _call(self, method: str, path: str, **kwargs: Any) -> Any:
        response = self.session.request(method, f"{self.base_url}/api/v1/{path}", timeout=30, **kwargs)
        response.raise_for_status()
        return response.json()

    def _lookup(self, path: str, key: str, value: str, what: str) -> dict:
        for item in self._call("GET", path):
            if item[key].rstrip("/") == value.rstrip("/"):
                return item
        raise LidarrConfigError(f"Lidarr has no {what} '{value}'")

    def _add_artist(self, artist_mbid: str) -> dict:
        root = self._lookup("rootfolder", "path", self.root_folder, "root folder")
        quality = self._lookup("qualityprofile", "name", self.quality_profile, "quality profile")
        metadata = self._lookup("metadataprofile", "name", self.metadata_profile, "metadata profile")
        found = self._call("GET", "artist/lookup", params={"term": f"lidarr:{artist_mbid}"})
        match = next((a for a in found if a.get("foreignArtistId") == artist_mbid), None)
        if match is None:
            raise LidarrConfigError(f"Lidarr lookup found no artist {artist_mbid}")
        return self._call(
            "POST",
            "artist",
            json={
                **match,
                "monitored": True,
                "monitorNewItems": "none",
                "rootFolderPath": root["path"],
                "qualityProfileId": quality["id"],
                "metadataProfileId": metadata["id"],
                "addOptions": {"monitor": "none", "searchForMissingAlbums": False},
            },
        )

    def _find_album(self, artist_id: int, release_group_mbid: str) -> dict | None:
        albums = self._call("GET", "album", params={"artistId": artist_id})
        return next((a for a in albums if a["foreignAlbumId"] == release_group_mbid), None)

    def _refresh(self, artist_id: int) -> None:
        command = self._call("POST", "command", json={"name": "RefreshArtist", "artistId": artist_id})
        for _ in range(REFRESH_ATTEMPTS):
            self.sleep(REFRESH_WAIT)
            status = self._call("GET", f"command/{command['id']}")["status"]
            if status == "completed" and not self._library_busy():
                return
            if status not in (*PENDING, "completed"):
                raise LidarrRefreshError(f"Lidarr refresh of artist {artist_id} {status}")
        raise LidarrRefreshError(f"Lidarr refresh of artist {artist_id} still running after {REFRESH_ATTEMPTS} checks")

    def _library_busy(self) -> bool:
        return any(c["name"] in LIBRARY_COMMANDS and c["status"] in PENDING for c in self._call("GET", "command"))

    def queue_album(self, artist_mbid: str, release_group_mbid: str) -> Literal["queued", "already", "owned"]:
        found = self._call("GET", "artist", params={"mbId": artist_mbid})
        artist = found[0] if found else self._add_artist(artist_mbid)
        album = self._find_album(artist["id"], release_group_mbid) if found else None
        if album is None:
            self._refresh(artist["id"])
            album = self._find_album(artist["id"], release_group_mbid)
        if album is None:
            raise AlbumNotFoundError(f"Lidarr has no album {release_group_mbid} for artist {artist['id']} after refreshing")
        if (album.get("statistics") or {}).get("trackFileCount", 0) > 0:
            return "owned"
        artist_was_monitored = artist.get("monitored", False)
        if not artist_was_monitored:
            self._call("PUT", f"artist/{artist['id']}", json={**artist, "monitored": True, "monitorNewItems": "none"})
        if album["monitored"]:
            if not artist_was_monitored:
                self._call("POST", "command", json={"name": "AlbumSearch", "albumIds": [album["id"]]})
            return "already"
        self._call("PUT", "album/monitor", json={"albumIds": [album["id"]], "monitored": True})
        self._call("POST", "command", json={"name": "AlbumSearch", "albumIds": [album["id"]]})
        return "queued"
