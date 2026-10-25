{
    den.aspects.game-status-http.nixos = {
        lib,
        config,
        pkgs,
        ...
    }: let
        cfg = config.services.gameStatusHttp;
        script = pkgs.writeText "game-status-http.py" ''
            import http.server, subprocess, json, os, socket, struct, threading

            PLAYER_STATE_DIR = ${builtins.toJSON cfg.playerStateDir}
            CONSOLES = json.loads(${builtins.toJSON (builtins.toJSON cfg.consoles)})
            RCON_PASS = os.environ.get("RCON_PASS", "")

            # Same RCON client as hosts/ds1/games/minecraft/hub/_update-counts.nix.
            def rcon(host, port, password, cmd):
                s = socket.socket()
                s.settimeout(5)
                s.connect((host, port))
                def send(t, i, p):
                    d = struct.pack('<ii', i, t) + p.encode('utf-8') + b'\x00\x00'
                    s.send(struct.pack('<i', len(d)) + d)
                def recv():
                    n = struct.unpack('<i', s.recv(4))[0]
                    d = b'''
                    while len(d) < n: d += s.recv(n - len(d))
                    return struct.unpack('<ii', d[:8])[0], d[8:-2].decode('utf-8')
                send(3, 1, password)
                recv()
                send(2, 1, cmd)
                _, r = recv()
                s.close()
                return r

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    if self.path.startswith('/console-logs/'):
                        self.handle_console_logs(self.path[len('/console-logs/'):])
                        return
                    svc = self.path.lstrip('/')
                    if not svc:
                        self.send_response(400)
                        self.end_headers()
                        return
                    r = subprocess.run(['systemctl', 'is-active', '--quiet', svc])
                    active = r.returncode == 0
                    payload = {'status': 'Running' if active else 'Stopped'}
                    player_file = os.path.join(PLAYER_STATE_DIR, f"{svc}.json")
                    if active and os.path.isfile(player_file):
                        try:
                            with open(player_file) as f:
                                payload['players'] = json.load(f)
                        except (OSError, json.JSONDecodeError):
                            # Unreadable/mid-write -- omit players, don't 500.
                            pass
                    body = json.dumps(payload).encode()
                    self.send_response(200 if active else 503)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def handle_console_logs(self, name):
                    console = CONSOLES.get(name)
                    if not console:
                        self.send_response(404)
                        self.end_headers()
                        return
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/event-stream')
                    self.send_header('Cache-Control', 'no-cache')
                    self.end_headers()
                    proc = subprocess.Popen(
                        ['journalctl', '-u', console['journalUnit'], '-n', '50', '-f', '-o', 'cat'],
                        stdout=subprocess.PIPE,
                        text=True,
                    )
                    try:
                        for line in proc.stdout:
                            self.wfile.write(f"data: {line.rstrip()}\n\n".encode())
                            self.wfile.flush()
                    except (BrokenPipeError, ConnectionResetError):
                        pass
                    finally:
                        proc.kill()

                def do_POST(self):
                    if not self.path.startswith('/console-command/'):
                        self.send_response(404)
                        self.end_headers()
                        return
                    name = self.path[len('/console-command/'):]
                    console = CONSOLES.get(name)
                    if not console:
                        self.send_response(404)
                        self.end_headers()
                        return
                    length = int(self.headers.get('Content-Length', 0))
                    try:
                        req_body = json.loads(self.rfile.read(length))
                        result = rcon('127.0.0.1', console['rconPort'], RCON_PASS, req_body['command'])
                        body = json.dumps({'response': result}).encode()
                        status = 200
                    except Exception as e:
                        body = json.dumps({'error': str(e)}).encode()
                        status = 502
                    self.send_response(status)
                    self.send_header('Content-Type', 'application/json')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)

                def log_message(self, *a):
                    pass

            http.server.ThreadingHTTPServer(('${cfg.address}', ${toString cfg.port}), Handler).serve_forever()
        '';
    in {
        options.services.gameStatusHttp = {
            address = lib.mkOption {
                type = lib.types.str;
                default = "127.0.0.1";
            };
            port = lib.mkOption {
                type = lib.types.port;
                default = 9909;
            };
            baseUrl = lib.mkOption {
                type = lib.types.str;
                default = "http://${cfg.address}:${toString cfg.port}";
                description = "Address dashboard widgets use to reach the status and console endpoints.";
            };
            playerStateDir = lib.mkOption {
                type = lib.types.str;
                default = "/run/hearth-players";
                description = "Directory the per-game notification scripts write <unit>.json player lists into, and this service serves them from.";
            };
            rconPasswordFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "EnvironmentFile supplying RCON_PASS for the console-command endpoint, declared by whichever game owns the RCON password.";
            };
            consoles = lib.mkOption {
                type = lib.types.attrsOf (lib.types.submodule {
                    options = {
                        rconPort = lib.mkOption {type = lib.types.port;};
                        journalUnit = lib.mkOption {type = lib.types.str;};
                    };
                });
                default = {};
                description = "Per-server RCON port + systemd journal unit for the live-console endpoints below, keyed by the same name my.dashboard.services already uses for that server.";
            };
        };

        config = {
            systemd.services.game-status-http = {
                description = "HTTP status endpoint for systemd services";
                wantedBy = ["multi-user.target"];
                path = [pkgs.systemd pkgs.util-linux];
                serviceConfig = {
                    ExecStart = "${pkgs.python3}/bin/python3 ${script}";
                    Restart = "on-failure";
                    RestartSec = "3s";
                    DynamicUser = true;
                    SupplementaryGroups = ["systemd-journal"];
                    EnvironmentFile = lib.mkIf (cfg.rconPasswordFile != null) cfg.rconPasswordFile;
                };
            };
        };
    };
}
