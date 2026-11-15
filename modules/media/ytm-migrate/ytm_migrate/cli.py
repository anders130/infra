import argparse
import json
import os
import sys
import zipfile
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import requests

from .identify import Cached, MusicBrainz, YouTubeMusic, album_key, identify_song, normalize, select
from .lidarr import Lidarr
from .listenbrainz import ListenBrainzError, submit_pending, validate_token
from .navidrome import ListenBrainzLinkedError, Navidrome
from . import review
from .state import State
from .takeout import read

STATE_DIR = "/var/lib/ytm-migrate"
DEFAULT_STATE = f"{STATE_DIR}/state.db"
UNLINK = (
    "unlink ListenBrainz in Navidrome's settings (Personal > ListenBrainz) and re-run, "
    "otherwise scrobbles would be duplicated"
)


@dataclass
class Clients:
    yt: Any
    mb: Any
    lidarr: Any
    navidrome: Any
    lb_session: Any
    lb_token: str


def _secret(env: dict, name: str) -> str:
    return Path(env[name]).read_text().strip()


def _playlists(env: dict) -> set[str]:
    raw = env.get("YTM_PLAYLISTS", "").strip()
    if raw.startswith("["):
        return set(json.loads(raw))
    return {line.strip() for line in raw.splitlines() if line.strip()}


def build_clients(env: dict) -> Clients:
    return Clients(
        yt=YouTubeMusic(),
        mb=MusicBrainz(),
        lidarr=Lidarr(
            env["LIDARR_URL"],
            _secret(env, "LIDARR_API_KEY_FILE"),
            env["LIDARR_ROOT_FOLDER"],
            env["LIDARR_QUALITY_PROFILE"],
            env["LIDARR_METADATA_PROFILE"],
        ),
        navidrome=Navidrome(env["NAVIDROME_URL"], env["NAVIDROME_USER"]),
        lb_session=requests.Session(),
        lb_token=_secret(env, "LISTENBRAINZ_TOKEN_FILE"),
    )


def _identify(state: State, clients: Clients) -> int:
    yt, mb = Cached(clients.yt, state, "yt"), Cached(clients.mb, state, "mb")
    liked = {s.video_id: s for s in state.liked()}
    errors = 0
    for song in state.songs("new"):
        try:
            identify_song(state, song, yt, mb, liked)
        except Exception as error:
            errors += 1
            print(f"identify {song.video_id} failed: {error}", file=sys.stderr)
    return errors


def _albums(state: State) -> list[tuple[str, str, str | None, str | None, list[str]]]:
    selected = set(select(state))
    groups: dict[str, list] = {}
    for song in state.songs("identified"):
        if song.song_key in selected and song.artist_mbid and song.release_group_mbid:
            groups.setdefault(song.release_group_mbid, []).append(song)
    return [
        (songs[0].artist_mbid, rg, songs[0].artist_name, songs[0].album, [s.video_id for s in songs])
        for rg, songs in groups.items()
    ]


def _owned(index: Any, artist: str | None, album: str | None) -> bool:
    return bool(artist and album and index.has_album(normalize(artist), album_key(album)))


def _checks(clients: Clients) -> bool:
    ok = True
    try:
        print(f"listenbrainz token: valid ({validate_token(clients.lb_session, clients.lb_token)})")
    except ListenBrainzError as error:
        print(f"listenbrainz token: invalid ({error})")
        ok = False
    try:
        clients.navidrome.check_listenbrainz()
        print("navidrome listenbrainz link: not linked")
    except ListenBrainzLinkedError:
        print(f"navidrome listenbrainz link: linked; {UNLINK}")
        ok = False
    return ok


def _apply(state: State, clients: Clients, index: Any) -> bool:
    ok = True
    try:
        result = submit_pending(state, clients.lb_token, clients.lb_session)
        print(f"listenbrainz sent: {result.sent}")
        print(f"listenbrainz skipped: {result.skipped}")
    except ListenBrainzError as error:
        print(f"listenbrainz step failed: {error}", file=sys.stderr)
        ok = False
    try:
        report = clients.navidrome.apply(state, index)
    except ListenBrainzLinkedError:
        print(f"navidrome step skipped: {UNLINK}")
        return False
    print(f"navidrome playlists created: {report.playlists_created}")
    print(f"navidrome playlists updated: {report.playlists_updated}")
    print(f"navidrome stars: {report.stars}")
    print(f"navidrome scrobbles: {report.scrobbles}")
    print(f"navidrome pending: {report.pending}")
    return ok


def run(zip_path: Path, dry_run: bool, state: State, clients: Clients, allowlist: set[str]) -> int:
    try:
        takeout = read(zip_path, allowlist)
    except (OSError, zipfile.BadZipFile, ValueError) as error:
        print(
            f"cannot read the Takeout export {zip_path}: {error}\n"
            f"place the Takeout .zip under {STATE_DIR} (readable by the ytm-migrate user) and pass its path",
            file=sys.stderr,
        )
        return 2
    new_plays = state.add_plays(takeout.history)
    state.set_playlists(takeout.playlists)
    state.set_liked(takeout.liked)
    errors = _identify(state, clients)

    index = clients.navidrome.index()
    queued = owned = 0
    for artist_mbid, rg_mbid, artist, album, video_ids in _albums(state):
        if _owned(index, artist, album):
            owned += 1
            if not dry_run:
                for video_id in video_ids:
                    state.set_status(video_id, "owned")
            continue
        if dry_run:
            queued += 1
            print(f"would queue {artist} - {album} ({artist_mbid} / {rg_mbid})")
            continue
        try:
            outcome = clients.lidarr.queue_album(artist_mbid, rg_mbid)
        except Exception as error:
            errors += 1
            print(f"queue {artist} - {album} failed: {error}", file=sys.stderr)
            continue
        status = "owned" if outcome == "owned" else "queued"
        owned += status == "owned"
        queued += status == "queued"
        for video_id in video_ids:
            state.set_status(video_id, status)

    review = len(state.review_items())
    print(f"new plays: {new_plays}")
    print(f"{'would-be ' if dry_run else ''}queued albums: {queued}")
    print(f"owned albums: {owned}")
    print(f"review: {review}")
    print(f"errors: {errors}")

    if dry_run:
        print(f"would submit listenbrainz listens: {len(state.pending_listens('listenbrainz'))}")
        print(f"would scrobble to navidrome: {len(state.pending_listens('navidrome'))}")
        ok = _checks(clients)
    else:
        ok = _apply(state, clients, index)
    return 0 if ok and errors == 0 else 1


def status(state: State) -> int:
    for name, count in sorted(Counter(s.status for s in state.songs()).items()):
        print(f"{name}: {count}")
    print(f"listenbrainz pending: {len(state.pending_listens('listenbrainz'))}")
    print(f"navidrome pending: {len(state.pending_listens('navidrome'))}")
    return 0


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(prog="ytm-migrate")
    commands = parser.add_subparsers(dest="command", required=True)
    run_parser = commands.add_parser("run")
    run_parser.add_argument("takeout", type=Path)
    run_parser.add_argument("--dry-run", action="store_true")
    commands.add_parser("status")
    review_parser = commands.add_parser("review")
    review_parser.add_argument("--port", type=int, default=review.DEFAULT_PORT)
    args = parser.parse_args(argv)
    env = dict(os.environ)
    state_path = Path(env.get("YTM_STATE", DEFAULT_STATE))
    state = State(state_path)
    if args.command == "review":
        review.serve(state_path, build_clients(env), args.port)
        return
    if args.command == "status":
        raise SystemExit(status(state))
    raise SystemExit(run(args.takeout, args.dry_run, state, build_clients(env), _playlists(env)))
