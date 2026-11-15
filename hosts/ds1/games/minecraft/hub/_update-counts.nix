{
    pkgs,
    lib,
    serverInfos,
    hubRconPort,
}:
pkgs.writeScript "mc-update-counts.py" ''
    #!/usr/bin/env python3
    import socket, struct, re, os

    def rcon(host, port, password, cmd):
        try:
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
        except Exception:
            return None

    pw = os.environ['RCON_PASS']
    HUB = ${toString hubRconPort}

    servers = [
    ${lib.concatMapStrings (s: ''
        {
            "name": "${s.serverName}",
            "displayName": "${s.displayName}",
            "color": "${s.color}",
            "subLine": "${s.subLine}",
            "motdLine": "${s.motdLine}",
            "port": ${toString s.rconPort},
        },
    '')
    serverInfos}
    ]

    for srv in servers:
        result = rcon('127.0.0.1', srv['port'], pw, 'list')
        if result is None:
            count_color, count_label = 'red', 'offline'
        else:
            clean = re.sub(r'§.', ''', result)
            m = re.match(r'There are (\d+)', clean)
            n = int(m.group(1)) if m else 0
            count_color = 'gray' if n == 0 else 'green'
            count_label = 'empty' if n == 0 else str(n) + ' online'

        tag = 'sinfo_display_' + srv['name']
        mk = 'portal_info_' + srv['name']

        nl = r'\\n'
        text = ('{"text":"","extra":['
            + '{"text":"' + srv['displayName'] + '","bold":true,"color":"' + srv['color'] + '"},'
            + '{"text":"' + nl + srv['subLine'] + '","color":"gray"},'
            + '{"text":"' + nl + srv['motdLine'] + '","color":"white"},'
            + '{"text":"' + nl + count_label + '","color":"' + count_color + '"}'
            + ']}')
        nbt = (
            '{text:' + "'" + text + "'"
            + ',alignment:"center",billboard:"center"'
            + ',Tags:["' + tag + '","server_display"]}'
        )

        rcon('127.0.0.1', HUB, pw, 'kill @e[tag=' + tag + ']')
        rcon('127.0.0.1', HUB, pw,
            'execute at @e[type=minecraft:marker,tag=' + mk + ',limit=1]'
            + ' run summon minecraft:text_display ~ ~2.0 ~ ' + nbt)
''
