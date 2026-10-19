import csv
import io
import json
import re
import sys
import zipfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlparse

LAYOUTS = [
    {
        "history": "YouTube und YouTube Music/Verlauf/Wiedergabeverlauf.json",
        "playlists": "YouTube und YouTube Music/Playlists/Playlists.csv",
        "playlist_dir": "YouTube und YouTube Music/Playlists",
        "library": "YouTube und YouTube Music/music (library and uploads)/music library songs.csv",
        "playlist_title": "Playlist-Titel (Original)",
        "video_id": "Video-ID",
    },
    {
        "history": "YouTube and YouTube Music/history/watch-history.json",
        "playlists": "YouTube and YouTube Music/playlists/playlists.csv",
        "playlist_dir": "YouTube and YouTube Music/playlists",
        "library": "YouTube and YouTube Music/music (library and uploads)/music library songs.csv",
        "playlist_title": "Playlist Title (Original)",
        "video_id": "Video ID",
    },
]

WATCHED_SUFFIXES = (" angesehen", " watched")
ARTIST_COLUMN = re.compile(r"Artist Name (\d+)$")


@dataclass(frozen=True)
class Play:
    video_id: str
    played_at: datetime
    title: str
    channel: str


@dataclass(frozen=True)
class LibrarySong:
    video_id: str
    title: str
    album: str
    artists: list[str]


@dataclass
class Takeout:
    history: list[Play] = field(default_factory=list)
    playlists: dict[str, list[str]] = field(default_factory=dict)
    liked: list[LibrarySong] = field(default_factory=list)


def _clean_title(title: str) -> str:
    for suffix in WATCHED_SUFFIXES:
        if title.endswith(suffix):
            return title.removesuffix(suffix)
    return title


def _video_id(url: str) -> str | None:
    ids = parse_qs(urlparse(url).query).get("v")
    return ids[0] if ids else None


def _parse_time(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def _plays(raw: bytes) -> list[Play]:
    plays = []
    for entry in json.loads(raw):
        if entry.get("header") != "YouTube Music" or "titleUrl" not in entry:
            continue
        video_id = _video_id(entry["titleUrl"])
        if video_id is None:
            continue
        subtitles = entry.get("subtitles") or [{}]
        plays.append(
            Play(
                video_id,
                _parse_time(entry["time"]),
                _clean_title(entry.get("title", "")),
                subtitles[0].get("name", ""),
            )
        )
    return plays


def _rows(raw: bytes) -> list[dict[str, str]]:
    return list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))


def _library(raw: bytes, id_column: str) -> list[LibrarySong]:
    songs = []
    for row in _rows(raw):
        video_id = (row.get(id_column) or "").strip()
        if not video_id:
            continue
        artist_columns = sorted(
            (int(m.group(1)), key)
            for key in row
            if (m := ARTIST_COLUMN.match(key))
        )
        artists = [row[key].strip() for _, key in artist_columns if (row[key] or "").strip()]
        songs.append(
            LibrarySong(video_id, row.get("Song Title") or "", row.get("Album Title") or "", artists)
        )
    return songs


def _playlists(
    archive: zipfile.ZipFile, root: str, layout: dict[str, str], allowlist: set[str]
) -> dict[str, list[str]]:
    result = {}
    for row in _rows(archive.read(root + layout["playlists"])):
        title = row[layout["playlist_title"]]
        if title not in allowlist:
            continue
        path = f"{root}{layout['playlist_dir']}/{title}-Videos.csv"
        if path not in archive.namelist():
            continue
        videos = archive.read(path)
        result[title] = [
            r[layout["video_id"]].strip() for r in _rows(videos) if (r.get(layout["video_id"]) or "").strip()
        ]
    for title in sorted(allowlist - result.keys()):
        print(f"warning: playlist '{title}' is not in the Takeout export", file=sys.stderr)
    return result


def _locate(names: list[str]) -> tuple[str, dict[str, str]] | None:
    for layout in LAYOUTS:
        for name in names:
            if name.endswith(layout["history"]):
                return name.removesuffix(layout["history"]), layout
            if name.endswith(layout["playlists"]):
                return name.removesuffix(layout["playlists"]), layout
    return None


def read(zip_path: Path, playlist_allowlist: set[str]) -> Takeout:
    with zipfile.ZipFile(zip_path) as archive:
        names = archive.namelist()
        located = _locate(names)
        if located is None:
            raise ValueError(f"{zip_path} is not a recognised YouTube Takeout export")
        root, layout = located
        takeout = Takeout()
        if root + layout["history"] in names:
            takeout.history = _plays(archive.read(root + layout["history"]))
        if root + layout["playlists"] in names:
            takeout.playlists = _playlists(archive, root, layout, playlist_allowlist)
        if root + layout["library"] in names:
            takeout.liked = _library(archive.read(root + layout["library"]), layout["video_id"])
        return takeout
