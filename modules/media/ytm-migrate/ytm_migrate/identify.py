import json
import re
import time
import unicodedata
from collections import Counter
from dataclasses import asdict, dataclass, field
from difflib import SequenceMatcher
from typing import Any, Callable, Literal, Protocol

import requests

from .state import State

USER_AGENT = "ytm-migrate/0.1 ( jesse.gollub@gmail.com )"
MUSICBRAINZ = "https://musicbrainz.org/ws/2/"
MUSIC_VIDEO_TYPES = {"MUSIC_VIDEO_TYPE_ATV", "MUSIC_VIDEO_TYPE_OMV"}
STATUS = {"confident": "identified", "review": "review", "not_music": "not_music"}
MAX_CANDIDATES = 5
SIMILAR_TITLE = 0.5
EDITION = re.compile(
    r"\s*[(\[](?![^)\]]*\b(remix|mix|live|acoustic|demo|instrumental)\b)"
    r"[^)\]]*\b(deluxe|remaster(ed)?|expanded|anniversary|edition|version|bonus tracks?)\b[^)\]]*[)\]]\s*$",
    re.IGNORECASE,
)
NOISE = re.compile(
    r"[(\[][^)\]]*\b(official|video|audio|lyrics?|visuali[sz]er|hd|4k|remaster(ed)?)\b[^)\]]*[)\]]",
    re.IGNORECASE,
)

Kind = Literal["confident", "review", "not_music"]


class YTLookup(Protocol):
    def song(self, video_id: str) -> dict: ...

    def watch_playlist(self, video_id: str) -> dict | None: ...


class MBLookup(Protocol):
    def search_artists(self, name: str) -> list[dict]: ...

    def release_groups(self, artist_mbid: str) -> list[dict]: ...

    def search_recordings(self, title: str, artist_mbid: str) -> list[dict]: ...

    def search_release_groups(self, artist: str, album: str) -> list[dict]: ...

    def release_group(self, mbid: str) -> dict: ...

    def release_group_of_release(self, mbid: str) -> str: ...


@dataclass(frozen=True)
class Known:
    title: str
    artists: list[str]
    album: str = ""
    liked: bool = False


@dataclass(frozen=True)
class Candidate:
    artist_mbid: str
    artist_name: str
    release_group_mbid: str | None = None
    release_group_title: str | None = None
    primary_type: str | None = None
    secondary_types: list[str] = field(default_factory=list)
    first_release_date: str | None = None
    disambiguation: str = ""
    credit_name: str | None = None
    credit_artist: str | None = None


@dataclass(frozen=True)
class Identity:
    kind: Kind
    artist_mbid: str | None
    release_group_mbid: str | None
    song_key: str
    candidates: list[Candidate]
    reason: str
    artist_name: str | None = None
    title: str | None = None
    album: str | None = None


@dataclass(frozen=True)
class Track:
    title: str
    artists: list[str]
    album: str


def normalize(text: str) -> str:
    folded = "".join(
        c for c in unicodedata.normalize("NFKD", text) if not unicodedata.combining(c)
    ).casefold()
    return " ".join(re.sub(r"[^\w\s]", " ", folded.replace("&", " and ")).split())


def strip_noise(title: str) -> str:
    return " ".join(NOISE.sub(" ", title).split())


def title_key(title: str) -> str:
    return normalize(strip_noise(title))


def album_key(album: str) -> str:
    while (stripped := EDITION.sub("", album)) != album:
        album = stripped
    return normalize(album)


def song_key(artist: str, title: str) -> str:
    return f"{normalize(artist)}|{title_key(title)}"


def lookup_key(method: str, args: tuple) -> str:
    return f"{method}:{json.dumps(list(args), ensure_ascii=False)}"


class Cached:
    def __init__(self, lookup: Any, state: State, namespace: str):
        self.lookup = lookup
        self.state = state
        self.namespace = namespace

    def __getattr__(self, method: str) -> Callable:
        fetch = getattr(self.lookup, method)
        return lambda *args: self.state.cached(
            self.namespace, lookup_key(method, args), lambda: fetch(*args)
        )


class YouTubeMusic:
    def __init__(self, api: Any = None):
        if api is None:
            from ytmusicapi import YTMusic

            api = YTMusic()
        self.api = api

    def song(self, video_id: str) -> dict:
        details = self.api.get_song(video_id).get("videoDetails") or {}
        return {"musicVideoType": details.get("musicVideoType")}

    def watch_playlist(self, video_id: str) -> dict | None:
        tracks = self.api.get_watch_playlist(videoId=video_id, limit=1).get("tracks") or []
        if not tracks:
            return None
        track = tracks[0]
        return {
            "videoId": track.get("videoId"),
            "title": track.get("title") or "",
            "artists": [a["name"] for a in track.get("artists") or [] if a.get("name")],
            "album": (track.get("album") or {}).get("name"),
            "videoType": track.get("videoType"),
        }


def _phrase(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _credit(artist_credit: list[dict]) -> dict:
    return {
        "credit": [c["artist"]["id"] for c in artist_credit],
        "credit-name": "".join(c["name"] + c.get("joinphrase", "") for c in artist_credit),
        "credit-artist": artist_credit[0]["artist"]["name"] if artist_credit else None,
    }


def _release_group(group: dict) -> dict:
    return {
        "id": group["id"],
        "title": group["title"],
        "primary-type": group.get("primary-type"),
        "secondary-types": group.get("secondary-types") or [],
        "first-release-date": group.get("first-release-date") or None,
    }


class MusicBrainz:
    def __init__(
        self,
        session: Any = None,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self.session = session or requests.Session()
        self.session.headers["User-Agent"] = USER_AGENT
        self.clock = clock
        self.sleep = sleep
        self.last: float | None = None

    def _get(self, path: str, **params: Any) -> dict:
        for attempt in range(7):
            if attempt:
                self.sleep(min(2**attempt, 60))
            if self.last is not None:
                wait = self.last + 1.0 - self.clock()
                if wait > 0:
                    self.sleep(wait)
            self.last = self.clock()
            response = self.session.get(
                MUSICBRAINZ + path, params={**params, "fmt": "json"}, timeout=30
            )
            if response.status_code != 503:
                break
        response.raise_for_status()
        return response.json()

    def search_artists(self, name: str) -> list[dict]:
        found = self._get("artist", query=f"artist:{_phrase(name)}", limit=10)
        return [
            {
                "id": a["id"],
                "name": a["name"],
                "score": int(a.get("score", 0)),
                "disambiguation": a.get("disambiguation", ""),
            }
            for a in found["artists"]
        ]

    def release_groups(self, artist_mbid: str) -> list[dict]:
        groups: list[dict] = []
        while True:
            page = self._get(
                "release-group",
                artist=artist_mbid,
                type="album",
                inc="artist-credits",
                limit=100,
                offset=len(groups),
            )
            batch = page["release-groups"]
            groups += [self._credited_group(group) for group in batch]
            if not batch or len(groups) >= page["release-group-count"]:
                return groups

    def _credited_group(self, group: dict) -> dict:
        return {**_release_group(group), **_credit(group.get("artist-credit") or [])}

    def search_release_groups(self, artist: str, album: str) -> list[dict]:
        found = self._get(
            "release-group",
            query=f"releasegroup:{_phrase(album)} AND artist:{_phrase(artist)}",
            limit=10,
        )
        return [self._credited_group(g) for g in found["release-groups"]]

    def release_group(self, mbid: str) -> dict:
        return self._credited_group(self._get(f"release-group/{mbid}", inc="artist-credits"))

    def release_group_of_release(self, mbid: str) -> str:
        return self._get(f"release/{mbid}", inc="release-groups")["release-group"]["id"]

    def search_recordings(self, title: str, artist_mbid: str) -> list[dict]:
        found = self._get(
            "recording", query=f"recording:{_phrase(title)} AND arid:{artist_mbid}", limit=25
        )
        return [
            {
                "id": r["id"],
                "title": r["title"],
                "release-groups": list(
                    {
                        rel["release-group"]["id"]: _release_group(rel["release-group"])
                        for rel in r.get("releases") or []
                        if "release-group" in rel
                    }.values()
                ),
            }
            for r in found["recordings"]
        ]


def _is_studio_album(group: dict) -> bool:
    return group["primary-type"] == "Album" and not group["secondary-types"]


def _candidate(artist: dict, group: dict | None = None) -> Candidate:
    if group is None:
        return Candidate(artist["id"], artist["name"], disambiguation=artist.get("disambiguation", ""))
    return Candidate(
        artist["id"],
        artist["name"],
        group["id"],
        group["title"],
        group["primary-type"],
        list(group["secondary-types"]),
        group["first-release-date"],
        artist.get("disambiguation", ""),
        group.get("credit-name"),
        group.get("credit-artist"),
    )


def _review(key: str, reason: str, track: Track | None, candidates: list[Candidate], artist: dict | None = None) -> Identity:
    return Identity(
        "review",
        artist["id"] if artist else None,
        None,
        key,
        candidates[:MAX_CANDIDATES],
        reason,
        track.artists[0] if track else None,
        track.title if track else None,
        track.album or None if track else None,
    )


def _unique_artist(name: str, results: list[dict]) -> dict | None:
    target = normalize(name)
    matching = [a for a in results if normalize(a["name"]) == target]
    if len(matching) != 1:
        return None
    [artist] = matching
    others = [a for a in results if a is not artist]
    if artist["score"] == 100 and all(a["score"] < 100 for a in others):
        return artist
    if all(a["score"] < 90 for a in others):
        return artist
    return None


def _youtube_track(video_id: str, yt: YTLookup, known: Known | None) -> Track | Identity:
    liked = known is not None and known.liked
    fallback = song_key(known.artists[0], known.title) if known and known.artists else f"video:{video_id}"
    watch = yt.watch_playlist(video_id)
    same = watch is not None and watch["videoId"] == video_id
    video_type = yt.song(video_id).get("musicVideoType") or (watch["videoType"] if same else None)
    if not liked and video_type is not None and video_type not in MUSIC_VIDEO_TYPES:
        return Identity("not_music", None, None, fallback, [], f"YouTube Music marks this video as {video_type}")
    if not same:
        returned = f"a different video ({watch['videoId']})" if watch else "nothing"
        return _review(fallback, f"YouTube Music returned {returned} for {video_id}; it is probably unavailable", None, [])
    if not liked and video_type is None:
        return _review(fallback, "YouTube Music does not say whether this video is a song", None, [])
    if not watch["artists"]:
        return _review(fallback, f"YouTube Music lists no artist for '{watch['title']}'", None, [])
    return Track(watch["title"], watch["artists"], watch["album"] or "")


def _similarity(album: str, title: str) -> float:
    return SequenceMatcher(None, normalize(album), normalize(title)).ratio() if album else 0.0


def _ranked(artist: dict, album: str, groups: list[dict]) -> list[Candidate]:
    ranked = sorted(
        groups,
        key=lambda g: (
            -(_similarity(album, g["title"]) + (0.1 if _is_studio_album(g) else 0)),
            g["first-release-date"] or "9999",
        ),
    )
    return [_candidate(artist, g) for g in ranked]


def _recording_groups(title: str, recordings: list[dict], groups: list[dict]) -> list[dict]:
    known = {g["id"]: g for g in groups}
    return list(
        {
            g["id"]: known.get(g["id"], g)
            for r in recordings
            if title_key(r["title"]) == title_key(title)
            for g in r["release-groups"]
        }.values()
    )


def _merge(*lists: list[Candidate]) -> list[Candidate]:
    seen: dict[tuple, Candidate] = {}
    for candidate in (c for candidates in lists for c in candidates):
        seen.setdefault((candidate.artist_mbid, candidate.release_group_mbid), candidate)
    return list(seen.values())[:MAX_CANDIDATES]


def _ambiguous_artist(track: Track, results: list[dict], mb: MBLookup) -> Identity:
    name = track.artists[0]
    key = song_key(name, track.title)
    matching = [a for a in results if normalize(a["name"]) == normalize(name) or a["score"] >= 90]
    if not matching:
        return _review(key, f"MusicBrainz has no artist named '{name}'", track, [])
    described = ", ".join(
        f"{a['name']} ({a['disambiguation']})" if a["disambiguation"] else a["name"] for a in matching[:MAX_CANDIDATES]
    )
    candidates = []
    for artist in matching[:MAX_CANDIDATES]:
        groups = mb.release_groups(artist["id"]) if track.album else []
        titled = [g for g in groups if normalize(g["title"]) == normalize(track.album)]
        candidates += [_candidate(artist, g) for g in titled] or [_candidate(artist)]
    return _review(
        key,
        f"Artist '{name}' is ambiguous: {len(matching)} MusicBrainz artists match ({described})",
        track,
        candidates,
    )


def _match(track: Track, mb: MBLookup) -> Identity:
    name = track.artists[0]
    results = mb.search_artists(name)
    artist = _unique_artist(name, results)
    if artist is None:
        return _ambiguous_artist(track, results, mb)
    recordings = mb.search_recordings(strip_noise(track.title), artist["id"])
    exact = {r["id"] for r in recordings if title_key(r["title"]) == title_key(track.title)}
    key = exact.pop() if len(exact) == 1 else song_key(name, track.title)
    groups = mb.release_groups(artist["id"])
    by_recording = _ranked(artist, track.album, _recording_groups(track.title, recordings, groups))
    if not track.album:
        return _review(key, f"YouTube Music lists no album for '{track.title}'", track, by_recording, artist)
    studio = [g for g in groups if _is_studio_album(g) and normalize(g["title"]) == normalize(track.album)]
    if not studio:
        studio = [g for g in groups if _is_studio_album(g) and album_key(g["title"]) == album_key(track.album)]
    if len(studio) != 1:
        reason = (
            f"'{artist['name']}' has no studio album titled '{track.album}' on MusicBrainz"
            if not studio
            else f"'{artist['name']}' has {len(studio)} studio albums titled '{track.album}' on MusicBrainz"
        )
        similar = _ranked(artist, track.album, [g for g in groups if _similarity(track.album, g["title"]) >= SIMILAR_TITLE])
        return _review(key, reason, track, _merge(similar, by_recording), artist)
    [group] = studio
    if group["credit"] != [artist["id"]]:
        return _review(
            key,
            f"MusicBrainz credits '{group['title']}' to '{group['credit-name']}', not '{artist['name']}' alone",
            track,
            [_candidate(artist, group)],
            artist,
        )
    return Identity(
        "confident",
        artist["id"],
        group["id"],
        key,
        [_candidate(artist, group)],
        f"'{group['title']}' is the only studio album of '{artist['name']}' matching '{track.album}'",
        artist["name"],
        track.title,
        group["title"],
    )


def identify(video_id: str, yt: YTLookup, mb: MBLookup, known: Known | None = None) -> Identity:
    if known is not None and known.liked and known.album and known.artists:
        return _match(Track(known.title, known.artists, known.album), mb)
    track = _youtube_track(video_id, yt, known)
    return track if isinstance(track, Identity) else _match(track, mb)


def _known(song, liked) -> Known | None:
    if liked is not None:
        return Known(liked.title, liked.artists, liked.album, liked=True)
    if song.title:
        return Known(song.title, [song.artist_name] if song.artist_name else [])
    return None


def identify_song(state: State, song, yt: YTLookup, mb: MBLookup, liked: dict) -> None:
    identity = identify(song.video_id, yt, mb, _known(song, liked.get(song.video_id)))
    state.set_identity(
        song.video_id,
        identity.song_key,
        identity.artist_mbid,
        identity.release_group_mbid,
        STATUS[identity.kind],
        identity.artist_name,
        identity.title,
        identity.album,
    )
    if identity.kind == "review":
        state.set_review(song.video_id, identity.reason, [asdict(c) for c in identity.candidates])


def identify_new(state: State, yt: YTLookup, mb: MBLookup) -> int:
    yt, mb = Cached(yt, state, "yt"), Cached(mb, state, "mb")
    liked = {s.video_id: s for s in state.liked()}
    songs = state.songs("new")
    for song in songs:
        identify_song(state, song, yt, mb, liked)
    return len(songs)


def select(state: State) -> list[str]:
    counts = state.play_counts()
    wanted = {s.video_id for s in state.liked()} | {v for ids in state.playlists().values() for v in ids}
    plays: Counter[str] = Counter()
    chosen = set()
    for song in state.songs():
        if song.song_key is None or song.status == "not_music":
            continue
        plays[song.song_key] += counts.get(song.video_id, 0)
        if song.video_id in wanted:
            chosen.add(song.song_key)
    return sorted(chosen | {key for key, n in plays.items() if n >= 2})
