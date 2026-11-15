import re
import threading
from dataclasses import dataclass
from html import escape
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

from .identify import album_key, normalize
from .state import State

DEFAULT_PORT = 8095
UUID = r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
MB_URL = re.compile(rf"musicbrainz\.org/(release-group|release)/({UUID})")
AUTOMATIC = ("identified", "queued", "owned")

SCRIPT = """
document.querySelectorAll(".toast:not(.pending)").forEach(t => t.onclick = () => t.remove());
"""

GROUPS = """
const groups = document.getElementById("groups");
const filter = document.getElementById("filter");
const sort = document.getElementById("sort");
const order = {
  artist: (a, b) => a.dataset.artist.localeCompare(b.dataset.artist),
  songs: (a, b) => b.dataset.songs - a.dataset.songs || order.artist(a, b),
  plays: (a, b) => b.dataset.plays - a.dataset.plays || order.artist(a, b),
};
function apply() {
  const query = filter.value.trim().toLowerCase();
  [...groups.children].sort(order[sort.value] || order.artist).forEach(g => {
    g.hidden = !g.dataset.text.includes(query);
    groups.append(g);
  });
  try { sessionStorage.setItem("reviewSort", sort.value); sessionStorage.setItem("reviewFilter", filter.value); } catch (e) {}
}
try { sort.value = sessionStorage.getItem("reviewSort") || "artist"; filter.value = sessionStorage.getItem("reviewFilter") || ""; } catch (e) {}
filter.oninput = sort.onchange = apply;
apply();
"""

KEEP_SCROLL = """
addEventListener("pagehide", () => { try { sessionStorage.setItem("reviewScroll", scrollY); } catch (e) {} });
try { scrollTo(0, Number(sessionStorage.getItem("reviewScroll")) || 0); } catch (e) {}
"""

STYLE = """
:root { color-scheme: light dark; --line: #8886; --dim: #888; }
body { font: 16px/1.4 system-ui, sans-serif; max-width: 42rem; margin: 0 auto; padding: 1rem; }
.card { border: 1px solid var(--line); border-radius: 8px; padding: 12px; margin: 12px 0; }
.label { font-size: .8em; text-transform: uppercase; letter-spacing: .04em; color: var(--dim); margin: 8px 0 2px; }
.dim { color: var(--dim); }
.toasts { position: fixed; top: 1rem; left: 1rem; right: 1rem; margin-left: auto; max-width: 24rem; display: flex; flex-direction: column; gap: 8px; z-index: 1; }
.toast { margin: 0; padding: 12px; border: 1px solid var(--line); border-radius: 8px; background: Canvas; color: CanvasText; box-shadow: 0 4px 16px #0005; cursor: pointer; animation: fade 0s 12s forwards; }
.toast.error { border-color: #c33; color: #c33; animation: none; }
.toast.pending { animation: none; cursor: default; }
@keyframes fade { to { opacity: 0; visibility: hidden; } }
.row { display: flex; gap: 8px; flex-wrap: wrap; margin-top: 8px; align-items: center; }
form { margin: 0; }
button, input { font: inherit; padding: 6px 12px; }
input[type=text] { flex: 1; min-width: 10rem; }
.big { font-size: 1.15em; }
.controls { position: sticky; top: 0; z-index: 1; background: Canvas; padding: 8px 0; margin: 0; }
select { font: inherit; padding: 6px; }
.group { border-top: 2px solid var(--line); margin-top: 20px; padding-top: 12px; }
.head { display: flex; gap: 12px; align-items: flex-start; }
.head > div { flex: 1; min-width: 0; }
.head p { margin: 0 0 4px; }
.cover { width: 96px; height: 96px; flex: none; border-radius: 6px; object-fit: cover; background: var(--line); }
.card p { margin: 4px 0; }
"""


@dataclass
class Response:
    status: int = 200
    body: str = ""
    location: str | None = None


def _redirect() -> Response:
    return Response(303, location="/")


def _page(title: str, content: str, refresh: bool = False, scripts: str = "") -> Response:
    meta = "<meta http-equiv=refresh content=5>" if refresh else ""
    script = SCRIPT + scripts
    return Response(
        body=f"<!doctype html><meta charset=utf-8><meta name=viewport content='width=device-width,initial-scale=1'>{meta}"
        f"<title>{escape(title)}</title><style>{STYLE}</style>{content}<script>{script}</script>"
    )


def _toasts(messages: list[tuple[str, bool]], pending: str = "") -> str:
    if not messages and not pending:
        return ""
    toasts = "".join(f"<p class='toast{' error' if failed else ''}'>{escape(m)}</p>" for m, failed in messages)
    return f"<div class=toasts>{pending}{toasts}</div>"


def _error(message: str) -> str:
    return _toasts([(message, True)])


def _post(action: str, label: str, **fields: str) -> str:
    hidden = "".join(f"<input type=hidden name={escape(k)} value='{escape(v, quote=True)}'>" for k, v in fields.items())
    return f"<form method=post action={action}>{hidden}<button>{label}</button></form>"


def _lidarr_artist(joined: str | None, first: str | None) -> str:
    if not first or joined == first:
        return ""
    return f"<span class=dim>Lidarr will add under: {escape(first)}</span>"


def _year(date: str | None) -> str:
    return (date or "")[:4]


def _link(url: str, text: str) -> str:
    return f"<a href='{escape(url, quote=True)}' target=_blank rel=noopener>{text}</a>"


def _cover(mbid: str | None) -> str:
    if not mbid:
        return "<div class=cover></div>"
    return (
        f"<img class=cover loading=lazy alt='' src='https://coverartarchive.org/release-group/{escape(mbid, quote=True)}/front-250'"
        " onerror=\"this.removeAttribute('src')\">"
    )


def _album_line(
    artist: str, title: str, kind: str | None, secondary: list[str], date: str | None, mbid: str | None
) -> str:
    detail = ", ".join(x for x in [_year(date), kind, *secondary] if x)
    suffix = f" <span class=dim>({escape(detail)})</span>" if detail else ""
    name = _link(f"https://musicbrainz.org/release-group/{mbid}", escape(title)) if mbid else escape(title)
    return f"<b>{escape(artist)}</b> — {name}{suffix}"


def _candidate_line(candidate: dict) -> str:
    return _album_line(
        candidate["artist_name"],
        candidate.get("release_group_title") or "(artist only, no album)",
        candidate.get("primary_type"),
        candidate.get("secondary_types") or [],
        candidate.get("first_release_date"),
        candidate.get("release_group_mbid"),
    )


def _group_line(group: dict) -> str:
    return _album_line(
        group["credit-name"], group["title"], group.get("primary-type"),
        group.get("secondary-types") or [], group.get("first-release-date"), group["id"],
    )


@dataclass
class _Group:
    artist: str
    best: dict | None
    songs: list[Any]


def _albums(state: State, song: Any) -> tuple[str, list[dict]]:
    reason, candidates = state.review_detail(song.video_id) or ("", [])
    return reason, [c for c in candidates if c.get("release_group_mbid")]


def _grouped(state: State, items: list[Any]) -> list[_Group]:
    groups: dict[tuple, _Group] = {}
    for song in items:
        _, albums = _albums(state, song)
        best = albums[0] if albums else None
        artist = best["artist_name"] if best else song.artist_name or ""
        key = ("album", best["release_group_mbid"]) if best else ("artist", normalize(artist))
        groups.setdefault(key, _Group(artist, best, [])).songs.append(song)
    return sorted(
        groups.values(),
        key=lambda g: (normalize(g.artist), normalize((g.best or {}).get("release_group_title") or "")),
    )


def _card(state: State, song: Any, best: dict | None, counts: dict[str, int], playlists: dict[str, list[str]], liked: set[str]) -> str:
    reason, albums = _albums(state, song)
    facts = [f"played {counts.get(song.video_id, 0)}×"]
    if song.video_id in liked:
        facts.append("liked")
    facts += [f"in playlist “{name}”" for name, ids in playlists.items() if song.video_id in ids]
    channel = state.channel(song.video_id)
    channel_part = f" — channel: <i>{escape(channel)}</i>" if channel else ""
    others = "<br>".join(_candidate_line(c) for c in albums if c != best)
    title = f"“{escape(song.title or song.video_id)}”"
    return (
        "<div class=card>"
        f"<p><b>{_link(f'https://music.youtube.com/watch?v={song.video_id}', title)}</b>{channel_part}"
        f"<br><span class=dim>{escape(' · '.join(facts))}</span></p>"
        + (f"<p class=dim>other options:<br>{others}</p>" if others else "")
        + f"<p class=dim>Why unsure: {escape(reason)}</p>"
        "<div class=row>"
        f"<form method=get action=/pick><input type=hidden name=video_id value='{escape(song.video_id, quote=True)}'>"
        "<button>↺ Pick another</button></form>"
        f"{_post('/skip', '✕ Skip', video_id=song.video_id)}</div></div>"
    )


def _section(state: State, group: _Group, counts: dict[str, int], playlists: dict[str, list[str]], liked: set[str]) -> str:
    plays = sum(counts.get(s.video_id, 0) for s in group.songs)
    n = len(group.songs)
    best = group.best
    if best:
        line = f"<p class=big>{_candidate_line(best)}</p>"
        label = "✓ Confirm album" if n == 1 else f"✓ Confirm album for all {n}"
        action = _post("/confirm", label, video_id=",".join(s.video_id for s in group.songs),
                       release_group_mbid=best["release_group_mbid"])
        action += _lidarr_artist(best.get("credit_name"), best.get("credit_artist"))
    else:
        line = f"<p class=big><b>{escape(group.artist)}</b> — <span class=dim>no album guess</span></p>"
        action = ""
    text = " ".join(
        [group.artist, (best or {}).get("release_group_title") or "", *(s.title or "" for s in group.songs)]
    ).lower()
    return (
        f"<section class=group data-artist='{escape(normalize(group.artist), quote=True)}' data-songs={n} data-plays={plays}"
        f" data-text='{escape(text, quote=True)}'>"
        f"<div class=head>{_cover(best and best['release_group_mbid'])}<div>{line}"
        f"<p class=dim>{n} song{'s' if n != 1 else ''} · {plays} plays</p><div class=row>{action}</div></div></div>"
        + "".join(_card(state, song, best, counts, playlists, liked) for song in group.songs)
        + "</section>"
    )


def index(state: State, error: str | None = None, notice: str | None = None) -> Response:
    items = state.review_items()
    automatic = sum(len(state.songs(status)) for status in AUTOMATIC)
    counts, playlists = state.play_counts(), state.playlists()
    liked = {s.video_id for s in state.liked()}
    groups = _grouped(state, items)
    sections = "".join(_section(state, g, counts, playlists, liked) for g in groups)
    header = f"<h2>{len(items)} left to review · {automatic} added automatically</h2>"
    controls = (
        "<div class='row controls'><input type=search id=filter placeholder='Filter by artist, album or song'>"
        "<select id=sort><option value=artist>Artist A–Z</option><option value=songs>Most songs</option>"
        "<option value=plays>Most played</option></select></div>"
        if groups
        else ""
    )
    messages = [(f"{video_id}: {message}", True) if failed else (message, False)
                for video_id, message, failed in state.pop_confirm_messages()]
    messages += [(error, True)] if error else []
    messages += [(notice, False)] if notice else []
    confirming = state.songs("confirming")
    pending = (
        "<div class='toast pending'><b>Being queued</b>"
        + "".join(f"<br><span class=dim>{escape(s.artist_name or '')} — {escape(s.title or s.video_id)}</span>" for s in confirming)
        + "</div>"
        if confirming
        else ""
    )
    return _page(
        "Music review",
        _toasts(messages, pending) + header + controls + f"<div id=groups>{sections}</div>",
        refresh=bool(confirming),
        scripts=(GROUPS if groups else "") + KEEP_SCROLL,
    )


def _group_choice(group: dict, video_id: str) -> str:
    return (
        f"<div class='card head'>{_cover(group['id'])}<div><p class=big>{_group_line(group)}</p>"
        f"<p class=dim>Artist: <b>{escape(group['credit-name'])}</b></p>"
        f"<div class=row>{_post('/confirm', '✓ Confirm this album', video_id=video_id, release_group_mbid=group['id'])}"
        f"{_lidarr_artist(group['credit-name'], group.get('credit-artist'))}</div></div></div>"
    )


def _pick_page(state: State, video_id: str, groups: list[dict], notice: str = "") -> Response:
    song = next((s for s in state.songs() if s.video_id == video_id), None)
    _, candidates = state.review_detail(video_id) or ("", [])
    stored = "".join(
        f"<div class='card head'>{_cover(c['release_group_mbid'])}<div><p class=big>{_candidate_line(c)}</p><div class=row>"
        f"{_post('/confirm', '✓ Confirm this album', video_id=video_id, release_group_mbid=c['release_group_mbid'])}"
        f"{_lidarr_artist(c.get('credit_name'), c.get('credit_artist'))}</div></div></div>"
        for c in candidates
        if c.get("release_group_mbid")
    )
    vid = escape(video_id, quote=True)
    forms = (
        f"<form method=post action=/pick><input type=hidden name=video_id value='{vid}'>"
        "<p class=label>Search MusicBrainz</p><div class=row>"
        "<input type=text name=artist placeholder=Artist><input type=text name=album placeholder=Album>"
        "<button>Search</button></div></form>"
        f"<form method=post action=/pick><input type=hidden name=video_id value='{vid}'>"
        "<p class=label>Or paste a MusicBrainz release-group URL</p><div class=row>"
        "<input type=text name=url placeholder=https://musicbrainz.org/release-group/…><button>Look up</button></div></form>"
    )
    found = "<p class=label>Result</p>" + "".join(_group_choice(g, video_id) for g in groups) if groups else ""
    title = escape(song.title or video_id) if song else vid
    return _page(
        "Pick another",
        f"<p><a href=/>← back</a></p><h2>Pick another for “{title}”</h2>{notice}{found}"
        f"<p class=label>Stored candidates</p>{stored or '<p class=dim>None.</p>'}{forms}",
    )


def pick_form(state: State, video_id: str) -> Response:
    return _pick_page(state, video_id, [])


def pick(state: State, clients: Any, form: dict[str, str]) -> Response:
    video_id = form.get("video_id", "")
    try:
        if form.get("url", "").strip():
            match = MB_URL.search(form["url"])
            if match is None:
                return _pick_page(state, video_id, [], _error("Not a MusicBrainz release-group or release URL."))
            kind, mbid = match.groups()
            if kind == "release":
                mbid = clients.mb.release_group_of_release(mbid)
            groups = [clients.mb.release_group(mbid)]
        else:
            groups = clients.mb.search_release_groups(form.get("artist", "").strip(), form.get("album", "").strip())
    except Exception as error:
        return _pick_page(state, video_id, [], _error(f"MusicBrainz lookup failed: {error}"))
    notice = "" if groups else "<p class=dim>Nothing found.</p>"
    return _pick_page(state, video_id, groups, notice)


def _start(job: Callable[[], None]) -> None:
    threading.Thread(target=job, daemon=True).start()


def confirm(
    state: State,
    clients: Any,
    form: dict[str, str],
    run: Callable[[Callable[[], None]], None] = _start,
    open_state: Callable[[], State] | None = None,
) -> Response:
    wanted = {v for v in form.get("video_id", "").split(",") if v}
    release_group = form.get("release_group_mbid", "")
    songs = [s for s in state.songs() if s.video_id in wanted and s.status == "review"]
    if not songs:
        return _redirect()
    for song in songs:
        state.set_status(song.video_id, "confirming")
    run(lambda: _finish_confirm((open_state or (lambda: state))(), clients, songs, release_group))
    return _redirect()


def _finish_confirm(state: State, clients: Any, songs: list[Any], release_group: str) -> None:
    try:
        group = clients.mb.release_group(release_group)
        artist_mbid = group["credit"][0]
        library = clients.navidrome.index()
        artists = {group["credit-name"], group.get("credit-artist")} - {None}
        owned = any(library.has_album(normalize(a), album_key(group["title"])) for a in artists)
        outcome = "owned" if owned else clients.lidarr.queue_album(artist_mbid, release_group)
    except Exception as error:
        for song in songs:
            state.set_status(song.video_id, "review")
        state.add_confirm_message(songs[0].video_id, str(error), error=True)
        return
    status = "owned" if outcome == "owned" else "queued"
    for song in songs:
        state.set_identity(
            song.video_id, song.song_key, artist_mbid, release_group, status, group["credit-name"], None, group["title"]
        )
    album = f"{group['credit-name']} — {group['title']}"
    message = {
        "owned": f"{album} is already in your library; nothing was queued.",
        "already": f"{album} was already wanted in Lidarr.",
    }.get(outcome, f"Queued {album} in Lidarr.")
    state.add_confirm_message(songs[0].video_id, message, error=False)


def skip(state: State, form: dict[str, str]) -> Response:
    state.set_status(form.get("video_id", ""), "skipped")
    return _redirect()


def route(
    method: str,
    path: str,
    query: dict[str, str],
    form: dict[str, str],
    state: State,
    clients: Any,
    open_state: Callable[[], State] | None = None,
) -> Response:
    if method == "GET" and path == "/":
        return index(state)
    if method == "GET" and path == "/pick":
        return pick_form(state, query.get("video_id", ""))
    if method == "POST" and path == "/confirm":
        return confirm(state, clients, form, open_state=open_state)
    if method == "POST" and path == "/pick":
        return pick(state, clients, form)
    if method == "POST" and path == "/skip":
        return skip(state, form)
    return Response(404, "not found")


def serve(state_path: Any, clients: Any, port: int) -> None:
    class Handler(BaseHTTPRequestHandler):
        def _respond(self, method: str, form: dict[str, str]) -> None:
            url = urlparse(self.path)
            query = {k: v[0] for k, v in parse_qs(url.query).items()}
            response = route(method, url.path, query, form, State(state_path), clients, lambda: State(state_path))
            self.send_response(response.status)
            if response.location:
                self.send_header("Location", response.location)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            body = response.body.encode()
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            self._respond("GET", {})

        def do_POST(self) -> None:
            length = int(self.headers.get("Content-Length") or 0)
            form = {k: v[0] for k, v in parse_qs(self.rfile.read(length).decode()).items()}
            self._respond("POST", form)

    State(state_path).reset_confirming()
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
