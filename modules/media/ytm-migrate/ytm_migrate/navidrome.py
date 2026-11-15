from dataclasses import dataclass, field
from typing import Any

import requests

from .identify import album_key, normalize, song_key
from .state import State

PAGE_SIZE = 500
API_VERSION = "1.16.1"
CLIENT = "ytm-migrate"


class NavidromeError(Exception):
    pass


class ListenBrainzLinkedError(NavidromeError):
    pass


def _album_artists(song: dict) -> set[str]:
    names = {song.get("artist"), song.get("albumArtist"), song.get("displayAlbumArtist")}
    names |= {a.get("name") for a in song.get("albumArtists") or []}
    return {n for n in names if n}


@dataclass
class LibraryIndex:
    by_mbid: dict[str, str] = field(default_factory=dict)
    by_key: dict[str, str] = field(default_factory=dict)
    albums: set[tuple[str, str]] = field(default_factory=set)

    def find(self, mbid: str | None, artist: str | None, title: str | None) -> str | None:
        if mbid and mbid in self.by_mbid:
            return self.by_mbid[mbid]
        if artist and title:
            return self.by_key.get(song_key(artist, title))
        return None

    def has_album(self, artist_norm: str, album_norm: str) -> bool:
        return (artist_norm, album_norm) in self.albums


@dataclass(frozen=True)
class ApplyReport:
    playlists_created: int
    playlists_updated: int
    stars: int
    scrobbles: int
    pending: int


class Navidrome:
    def __init__(self, base_url: str = "http://127.0.0.1:4533", username: str = "", session: Any = None):
        self.base_url = base_url.rstrip("/")
        self.username = username
        self.headers = {"Remote-User": username}
        self.session = session or requests.Session()

    def _get(self, path: str, params: list[tuple[str, Any]] | None = None) -> Any:
        query = [("v", API_VERSION), ("c", CLIENT), ("f", "json"), *(params or [])]
        response = self.session.get(f"{self.base_url}{path}", params=query, headers=self.headers, timeout=60)
        return response

    def _rest(self, name: str, *params: tuple[str, Any]) -> dict:
        response = self._get(f"/rest/{name}", list(params))
        response.raise_for_status()
        body = response.json()["subsonic-response"]
        if body.get("status") != "ok":
            raise NavidromeError(f"{name} failed: {body.get('error')}")
        return body

    def check_listenbrainz(self) -> None:
        response = self._get("/api/listenbrainz/link")
        if response.status_code == 404:
            return
        response.raise_for_status()
        if response.json().get("status"):
            raise ListenBrainzLinkedError(
                "Navidrome user has ListenBrainz linked; unlink it first or scrobbles would be duplicated"
            )

    def index(self) -> LibraryIndex:
        index = LibraryIndex()
        offset = 0
        while True:
            body = self._rest(
                "search3",
                ("query", '""'),
                ("songCount", PAGE_SIZE),
                ("songOffset", offset),
                ("artistCount", 0),
                ("albumCount", 0),
            )
            songs = body.get("searchResult3", {}).get("song", [])
            for s in songs:
                if s.get("musicBrainzId"):
                    index.by_mbid[s["musicBrainzId"]] = s["id"]
                if s.get("artist") and s.get("title"):
                    index.by_key.setdefault(song_key(s["artist"], s["title"]), s["id"])
                if s.get("album"):
                    for artist in _album_artists(s):
                        index.albums.add((normalize(artist), album_key(s["album"])))
            if len(songs) < PAGE_SIZE:
                return index
            offset += PAGE_SIZE

    def _playlist_entries(self, playlist_id: str) -> list[str]:
        body = self._rest("getPlaylist", ("id", playlist_id))
        return [e["id"] for e in body["playlist"].get("entry", [])]

    def _sync_playlist(self, existing: dict[str, str], name: str, ids: list[str]) -> str | None:
        playlist_id = existing.get(name)
        songs = [("songId", i) for i in ids]
        if playlist_id is None:
            self._rest("createPlaylist", ("name", name), *songs)
            return "created"
        present = set(self._playlist_entries(playlist_id))
        missing = [("songIdToAdd", i) for i in ids if i not in present]
        if not missing:
            return None
        self._rest("updatePlaylist", ("playlistId", playlist_id), *missing)
        return "updated"

    def apply(self, state: State, index: LibraryIndex) -> ApplyReport:
        self.check_listenbrainz()
        songs = {s.video_id: s for s in state.songs()}

        def lookup(video_id: str, title: str | None = None, artist: str | None = None) -> str | None:
            song = songs.get(video_id)
            if song is None:
                return index.find(None, artist, title)
            by_key = song.song_key if song.song_key and "|" in song.song_key else None
            return (
                index.find(song.song_key, song.artist_name or artist, song.title or title)
                or (index.by_key.get(by_key) if by_key else None)
            )

        pending = 0
        created = updated = stars = scrobbles = 0

        existing = {
            p["name"]: p["id"]
            for p in self._rest("getPlaylists").get("playlists", {}).get("playlist", [])
            if p.get("owner") == self.username
        }
        for name, video_ids in state.playlists().items():
            found = [lookup(v) for v in video_ids]
            ids = list(dict.fromkeys(i for i in found if i))
            pending += sum(1 for i in found if i is None)
            if not ids:
                continue
            outcome = self._sync_playlist(existing, name, ids)
            created += outcome == "created"
            updated += outcome == "updated"

        for liked in state.liked():
            song_id = lookup(liked.video_id, liked.title, liked.artists[0] if liked.artists else None)
            if song_id is None:
                pending += 1
            elif not state.is_applied("star", song_id):
                self._rest("star", ("id", song_id))
                state.mark_applied("star", song_id)
                stars += 1

        for play in state.pending_listens("navidrome"):
            song_id = lookup(play.video_id, play.title, play.channel.removesuffix(" - Topic"))
            if song_id is None:
                pending += 1
                continue
            self._rest(
                "scrobble",
                ("id", song_id),
                ("time", int(play.played_at.timestamp() * 1000)),
                ("submission", "true"),
            )
            state.mark_sent("navidrome", [(play.video_id, play.played_at)])
            scrobbles += 1

        return ApplyReport(created, updated, stars, scrobbles, pending)
