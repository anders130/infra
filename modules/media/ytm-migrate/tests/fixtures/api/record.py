"""Re-record ytmusic.json and musicbrainz.json from the live APIs.

PYTHONPATH=modules/media/ytm-migrate python3 modules/media/ytm-migrate/tests/fixtures/api/record.py
"""

import json
from pathlib import Path

from ytm_migrate.identify import Known, MusicBrainz, YouTubeMusic, identify, lookup_key

HERE = Path(__file__).parent


def history(title, artist):
    return Known(title, [artist])


def liked(title, album, *artists):
    return Known(title, list(artists), album, liked=True)


CASES = [
    ("Y2Duog7ZWcA", history("Down To The Waterline", "Dire Straits")),
    ("N47SWUcYhQU", history("Mammagamma", "The Alan Parsons Project")),
    ("vB8dweYCLes", history("I Robot", "The Alan Parsons Project")),
    ("vB8dweYCLes", liked("I Robot", "I Robot", "The Alan Parsons Project")),
    ("XsCPCmpNeto", liked("(Sittin' On) The Dock of the Bay", "Accomplice One", "Tommy Emmanuel", "J.D. Simo")),
    ("XsCPCmpNeto", history("(Sittin' On) The Dock of the Bay", "Tommy Emmanuel")),
    (
        "D1E9mjvGYq8",
        liked(
            "(The System Of) Doctor Tarr And Professor Fether (1987 Remix)",
            "Tales Of Mystery And Imagination - Edgar Allan Poe (1987 Remix)",
            "The Alan Parsons Project",
            "Alan Parsons",
            "Eric Woolfson",
        ),
    ),
    (
        "IEnc5F2eHZw",
        liked(
            "(The System Of) Doctor Tarr And Professor Fether",
            "Tales Of Mystery And Imagination (Original 1976 Version)",
            "The Alan Parsons Project",
        ),
    ),
    ("4UnU3r0M3zg", history("Under the Bridge", "Red Hot Chili Peppers")),
    ("GLvohMXgcBo", history("Under The Bridge", "Red Hot Chili Peppers")),
    ("H4rBLGmbe80", history("Soul to Squeeze", "Red Hot Chili Peppers")),
    ("n50LrYEcqo4", liked("Cheer Up, Boys (Your Make Up Is Running)", "Echoes, Silence, Patience & Grace", "Foo Fighters")),
    ("n50LrYEcqo4", history("Cheer Up, Boys (Your Make Up Is Running)", "Foo Fighters")),
    ("PzP8mw7JUzI", history("WPF C# Professional Modern Flat UI Tutorial", "Payload")),
]


class Recorder:
    def __init__(self, lookup):
        self.lookup = lookup
        self.responses = {}

    def __getattr__(self, method):
        fetch = getattr(self.lookup, method)

        def call(*args):
            key = lookup_key(method, args)
            if key not in self.responses:
                self.responses[key] = fetch(*args)
            return self.responses[key]

        return call


def dump(responses):
    entries = (
        f" {json.dumps(k, ensure_ascii=False)}: {json.dumps(v, ensure_ascii=False)}"
        for k, v in sorted(responses.items())
    )
    return "{\n" + ",\n".join(entries) + "\n}\n"


def main():
    yt, mb = Recorder(YouTubeMusic()), Recorder(MusicBrainz())
    for video_id, known in CASES:
        identity = identify(video_id, yt, mb, known)
        print(video_id, identity.kind, identity.release_group_mbid, identity.song_key, "|", identity.reason)
    (HERE / "ytmusic.json").write_text(dump(yt.responses))
    (HERE / "musicbrainz.json").write_text(dump(mb.responses))


if __name__ == "__main__":
    main()
