import json
import sqlite3
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, Iterable, Literal

from .takeout import LibrarySong, Play

Status = Literal["new", "identified", "review", "confirming", "skipped", "queued", "owned", "not_music"]
Target = Literal["listenbrainz", "navidrome"]

SENT_COLUMN = {"listenbrainz": "sent_listenbrainz", "navidrome": "sent_navidrome"}

SCHEMA = """
create table if not exists plays (
    video_id text not null,
    played_at text not null,
    title text not null,
    channel text not null,
    sent_listenbrainz integer not null default 0,
    sent_navidrome integer not null default 0,
    primary key (video_id, played_at)
);
create table if not exists songs (
    video_id text primary key,
    song_key text,
    artist_mbid text,
    release_group_mbid text,
    status text not null default 'new',
    artist_name text,
    title text,
    album text
);
create table if not exists playlists (
    name text not null,
    position integer not null,
    video_id text not null,
    primary key (name, position)
);
create table if not exists liked (
    position integer primary key,
    video_id text not null,
    title text not null,
    album text not null,
    artists text not null
);
create table if not exists reviews (
    video_id text primary key,
    reason text not null,
    candidates text not null
);
create table if not exists lookups (
    kind text not null,
    key text not null,
    response text not null,
    primary key (kind, key)
);
create table if not exists applied (
    kind text not null,
    key text not null,
    primary key (kind, key)
);
create table if not exists confirm_messages (
    id integer primary key,
    video_id text not null,
    message text not null,
    error integer not null
);
"""


@dataclass(frozen=True)
class Song:
    video_id: str
    song_key: str | None
    artist_mbid: str | None
    release_group_mbid: str | None
    status: str
    artist_name: str | None
    title: str | None
    album: str | None


def _iso(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat()


class State:
    def __init__(self, path: Path):
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.executescript(SCHEMA)
        with self.db:
            self.db.execute("delete from songs where video_id != trim(video_id)")

    def add_plays(self, plays: Iterable[Play]) -> int:
        inserted = 0
        with self.db:
            for play in plays:
                cursor = self.db.execute(
                    "insert or ignore into plays (video_id, played_at, title, channel) values (?, ?, ?, ?)",
                    (play.video_id, _iso(play.played_at), play.title, play.channel),
                )
                inserted += cursor.rowcount
                self.db.execute(
                    "insert or ignore into songs (video_id, title, artist_name) values (?, ?, ?)",
                    (play.video_id, play.title, play.channel.removesuffix(" - Topic")),
                )
        return inserted

    def set_playlists(self, playlists: dict[str, list[str]]) -> None:
        with self.db:
            self.db.execute("delete from playlists")
            self.db.executemany(
                "insert into playlists (name, position, video_id) values (?, ?, ?)",
                [
                    (name, position, video_id)
                    for name, video_ids in playlists.items()
                    for position, video_id in enumerate(video_ids)
                ],
            )
            self._ensure_songs(v for ids in playlists.values() for v in ids)

    def set_liked(self, liked: Iterable[LibrarySong]) -> None:
        liked = list(liked)
        with self.db:
            self.db.execute("delete from liked")
            self.db.executemany(
                "insert into liked (position, video_id, title, album, artists) values (?, ?, ?, ?, ?)",
                [
                    (i, s.video_id, s.title, s.album, json.dumps(s.artists))
                    for i, s in enumerate(liked)
                ],
            )
            for song in liked:
                self.db.execute(
                    """
                    insert into songs (video_id, title, album, artist_name) values (?, ?, ?, ?)
                    on conflict (video_id) do update set
                        title = coalesce(nullif(excluded.title, ''), title),
                        album = coalesce(nullif(excluded.album, ''), album),
                        artist_name = coalesce(excluded.artist_name, artist_name)
                    """,
                    (song.video_id, song.title, song.album, song.artists[0] if song.artists else None),
                )

    def _ensure_songs(self, video_ids: Iterable[str]) -> None:
        self.db.executemany(
            "insert or ignore into songs (video_id) values (?)",
            [(v,) for v in video_ids],
        )

    def playlists(self) -> dict[str, list[str]]:
        result: dict[str, list[str]] = {}
        for row in self.db.execute("select name, video_id from playlists order by name, position"):
            result.setdefault(row["name"], []).append(row["video_id"])
        return result

    def liked(self) -> list[LibrarySong]:
        return [
            LibrarySong(r["video_id"], r["title"], r["album"], json.loads(r["artists"]))
            for r in self.db.execute("select * from liked order by position")
        ]

    def songs(self, status: str | None = None) -> list[Song]:
        query = "select * from songs"
        args: tuple = ()
        if status is not None:
            query += " where status = ?"
            args = (status,)
        return [Song(**dict(r)) for r in self.db.execute(query + " order by video_id", args)]

    def set_identity(
        self,
        video_id: str,
        song_key: str | None,
        artist_mbid: str | None,
        release_group_mbid: str | None,
        status: str,
        artist_name: str | None = None,
        title: str | None = None,
        album: str | None = None,
    ) -> None:
        with self.db:
            self.db.execute(
                """
                insert into songs (video_id, song_key, artist_mbid, release_group_mbid, status, artist_name, title, album)
                values (?, ?, ?, ?, ?, ?, ?, ?)
                on conflict (video_id) do update set
                    song_key = excluded.song_key,
                    artist_mbid = excluded.artist_mbid,
                    release_group_mbid = excluded.release_group_mbid,
                    status = excluded.status,
                    artist_name = coalesce(excluded.artist_name, artist_name),
                    title = coalesce(excluded.title, title),
                    album = coalesce(excluded.album, album)
                """,
                (video_id, song_key, artist_mbid, release_group_mbid, status, artist_name, title, album),
            )

    def set_status(self, video_id: str, status: str) -> None:
        with self.db:
            self.db.execute("update songs set status = ? where video_id = ?", (status, video_id))

    def reset_confirming(self) -> None:
        with self.db:
            self.db.execute("update songs set status = 'review' where status = 'confirming'")

    def add_confirm_message(self, video_id: str, message: str, error: bool) -> None:
        with self.db:
            self.db.execute(
                "insert into confirm_messages (video_id, message, error) values (?, ?, ?)",
                (video_id, message, int(error)),
            )

    def pop_confirm_messages(self) -> list[tuple[str, str, bool]]:
        with self.db:
            rows = self.db.execute("select video_id, message, error from confirm_messages order by id").fetchall()
            self.db.execute("delete from confirm_messages")
        return [(row["video_id"], row["message"], bool(row["error"])) for row in rows]

    def channel(self, video_id: str) -> str | None:
        row = self.db.execute("select channel from plays where video_id = ? limit 1", (video_id,)).fetchone()
        return None if row is None else row["channel"]

    def review_items(self) -> list[Song]:
        return self.songs("review")

    def pending_listens(self, target: Target) -> list[Play]:
        column = SENT_COLUMN[target]
        status_filter = (
            "and s.status in ('identified', 'queued', 'owned')" if target == "navidrome" else "and s.status != 'not_music'"
        )
        rows = self.db.execute(
            f"""
            select p.video_id, p.played_at, p.title, p.channel
            from plays p join songs s using (video_id)
            where p.{column} = 0 {status_filter}
            order by p.played_at
            """
        )
        return [
            Play(r["video_id"], datetime.fromisoformat(r["played_at"]), r["title"], r["channel"])
            for r in rows
        ]

    def mark_sent(self, target: Target, keys: Iterable[tuple[str, datetime]]) -> None:
        column = SENT_COLUMN[target]
        with self.db:
            self.db.executemany(
                f"update plays set {column} = 1 where video_id = ? and played_at = ?",
                [(video_id, _iso(played_at)) for video_id, played_at in keys],
            )

    def set_review(self, video_id: str, reason: str, candidates: list[dict]) -> None:
        with self.db:
            self.db.execute(
                "insert or replace into reviews (video_id, reason, candidates) values (?, ?, ?)",
                (video_id, reason, json.dumps(candidates)),
            )

    def review_detail(self, video_id: str) -> tuple[str, list[dict]] | None:
        row = self.db.execute(
            "select reason, candidates from reviews where video_id = ?", (video_id,)
        ).fetchone()
        return None if row is None else (row["reason"], json.loads(row["candidates"]))

    def cached(self, kind: str, key: str, fetch: Callable[[], Any]) -> Any:
        row = self.db.execute(
            "select response from lookups where kind = ? and key = ?", (kind, key)
        ).fetchone()
        if row is not None:
            return json.loads(row["response"])
        response = fetch()
        with self.db:
            self.db.execute(
                "insert into lookups (kind, key, response) values (?, ?, ?)",
                (kind, key, json.dumps(response)),
            )
        return response

    def play_counts(self) -> dict[str, int]:
        return {
            r["video_id"]: r["n"]
            for r in self.db.execute("select video_id, count(*) as n from plays group by video_id")
        }

    def mark_applied(self, kind: str, key: str) -> None:
        with self.db:
            self.db.execute("insert or ignore into applied (kind, key) values (?, ?)", (kind, key))

    def is_applied(self, kind: str, key: str) -> bool:
        return self.db.execute(
            "select 1 from applied where kind = ? and key = ?", (kind, key)
        ).fetchone() is not None
