#!/usr/bin/env python3
import http.server
import os
import html
import urllib.parse

SERVERS = @servers@
ACTIVE_FILE = "@velocityDataDir@/active-server"
DEFAULT_SERVER = "@defaultServer@"
PORT = @adminPort@


def get_active():
    try:
        s = open(ACTIVE_FILE).read().strip()
        if s in SERVERS:
            return s
    except OSError:
        pass
    return DEFAULT_SERVER


PAGE_STYLE = """
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; max-width: 480px; margin: 48px auto; padding: 0 24px; }
h1 { font-size: 1.4rem; margin-bottom: 6px; }
.sub { color: #666; margin-bottom: 28px; font-size: 0.9rem; }
ul { list-style: none; }
li { margin: 10px 0; }
button {
    width: 100%; padding: 12px 16px; border: 2px solid #ddd; border-radius: 8px;
    background: #fff; font-size: 1rem; text-align: left; cursor: pointer;
    display: flex; justify-content: space-between; align-items: center;
    transition: border-color .15s;
}
button:hover:not(:disabled) { border-color: #888; }
button.active { border-color: #22a; background: #f4f4ff; font-weight: 600; cursor: default; }
.badge { font-size: 0.75rem; background: #22a; color: #fff; padding: 2px 8px; border-radius: 12px; }
@media (prefers-color-scheme: dark) {
    body { background: #111; color: #eee; }
    .sub { color: #aaa; }
    button { background: #1e1e1e; border-color: #444; color: #eee; }
    button:hover:not(:disabled) { border-color: #aaa; }
    button.active { border-color: #66f; background: #1a1a2e; }
    .badge { background: #66f; }
}
"""


class AdminHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def do_GET(self):
        if self.path != "/":
            self.send_response(404)
            self.end_headers()
            return
        active = get_active()
        items = ""
        for s in SERVERS:
            is_active = s == active
            badge = '<span class="badge">active</span>' if is_active else ""
            escaped = html.escape(s)
            cls = ' class="active"' if is_active else ""
            dis = " disabled" if is_active else ""
            items += (
                f'<li><form method="POST" action="/">'
                f'<input type="hidden" name="server" value="{escaped}">'
                f'<button{cls} type="submit"{dis}>'
                f"{escaped}{' ' + badge if badge else ''}</button></form></li>\n"
            )
        page = f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Velocity Admin</title><style>{PAGE_STYLE}</style></head>
<body>
<h1>Velocity</h1>
<p class="sub">Players connecting to mc.gollub.dev join: <strong>{html.escape(active)}</strong></p>
<ul>{items}</ul>
</body></html>"""
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(page.encode())

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        data = urllib.parse.parse_qs(self.rfile.read(n).decode())
        server = (data.get("server") or [""])[0].strip()
        if server not in SERVERS:
            self.send_response(400)
            self.end_headers()
            return
        try:
            with open(ACTIVE_FILE, "w") as f:
                f.write(server)
        except OSError as e:
            self.send_response(500)
            self.end_headers()
            self.wfile.write(str(e).encode())
            return
        self.send_response(303)
        self.send_header("Location", "/")
        self.end_headers()


if __name__ == "__main__":
    http.server.HTTPServer(("127.0.0.1", PORT), AdminHandler).serve_forever()
