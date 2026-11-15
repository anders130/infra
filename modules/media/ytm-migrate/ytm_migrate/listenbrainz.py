import time
from dataclasses import dataclass
from typing import Any, Callable

from .state import State

URL = "https://api.listenbrainz.org/1/submit-listens"
VALIDATE_URL = "https://api.listenbrainz.org/1/validate-token"
BATCH_SIZE = 1000
DEFAULT_RESET_WAIT = 10
MAX_RATE_LIMIT_RETRIES = 5


class ListenBrainzError(Exception):
    pass


@dataclass(frozen=True)
class SubmitResult:
    sent: int
    skipped: int


def _metadata(play: Any, song: Any) -> dict | None:
    artist = ((song.artist_name if song else None) or play.channel.removesuffix(" - Topic")).strip()
    track = ((song.title if song else None) or play.title).strip()
    if not artist or not track:
        return None
    metadata = {"artist_name": artist, "track_name": track}
    if song and song.album:
        metadata["release_name"] = song.album
    return metadata


def _reset_wait(response: Any) -> int:
    try:
        return int(float(response.headers.get("X-RateLimit-Reset-In", DEFAULT_RESET_WAIT)))
    except (TypeError, ValueError, OverflowError):
        return DEFAULT_RESET_WAIT


def validate_token(session: Any, token: str) -> str:
    try:
        response = session.get(VALIDATE_URL, headers={"Authorization": f"Token {token}"}, timeout=30)
        body = response.json()
    except Exception as error:
        raise ListenBrainzError(f"could not reach ListenBrainz: {error}") from error
    if response.status_code != 200 or not body.get("valid"):
        raise ListenBrainzError(f"ListenBrainz rejected the token: {body.get('message', response.status_code)}")
    return body.get("user_name") or "?"


def _post(session: Any, token: str, payload: list[dict], sleep: Callable[[float], None]) -> None:
    for attempt in range(MAX_RATE_LIMIT_RETRIES + 1):
        response = session.post(
            URL,
            headers={"Authorization": f"Token {token}"},
            json={"listen_type": "import", "payload": payload},
            timeout=60,
        )
        if response.status_code == 200:
            return
        if response.status_code != 429:
            raise ListenBrainzError(
                f"ListenBrainz returned HTTP {response.status_code}: {getattr(response, 'text', '')}"
            )
        if attempt < MAX_RATE_LIMIT_RETRIES:
            sleep(_reset_wait(response))
    raise ListenBrainzError(f"ListenBrainz still rate limiting after {MAX_RATE_LIMIT_RETRIES} retries (HTTP 429)")


def submit_pending(
    state: State,
    token: str,
    session: Any,
    sleep: Callable[[float], None] = time.sleep,
) -> SubmitResult:
    songs = {song.video_id: song for song in state.songs()}
    pending = state.pending_listens("listenbrainz")
    sent = skipped = 0
    for start in range(0, len(pending), BATCH_SIZE):
        batch = pending[start : start + BATCH_SIZE]
        payload = []
        for play in batch:
            metadata = _metadata(play, songs.get(play.video_id))
            if metadata is None:
                skipped += 1
                continue
            payload.append({"listened_at": int(play.played_at.timestamp()), "track_metadata": metadata})
        if payload:
            _post(session, token, payload, sleep)
        state.mark_sent("listenbrainz", [(p.video_id, p.played_at) for p in batch])
        sent += len(payload)
    return SubmitResult(sent, skipped)
