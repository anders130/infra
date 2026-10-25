{
    self,
    lib,
    ...
}: {
    den.aspects.gameRelay.nixos = {config, ...}: let
        thisHost = config.networking.hostName;

        relevantRoutes = builtins.filter
        (r: r.via.config.networking.hostName == thisHost)
        (self.relay or []);

        peers = map (r: {
            ip = r.from.config.my.networking.tailscaleIP;
            ports = r.ports r.from.config;
        })
        relevantRoutes;

        allTcpPorts = lib.concatMap (p: p.ports.tcp or []) peers;
        allUdpPorts = lib.concatMap (p: p.ports.udp or []) peers;
    in {
        options.my.services.gameRelay.externalInterface = lib.mkOption {
            type = lib.types.str;
            default = "enp1s0";
        };

        config = lib.mkIf (peers != []) {
            networking.nat = {
                enable = true;
                externalInterface = config.my.services.gameRelay.externalInterface;
                forwardPorts = lib.concatMap (p:
                    map (port: {
                        destination = "${p.ip}:${toString port}";
                        proto = "tcp";
                        sourcePort = port;
                    })
                    (p.ports.tcp or [])
                    ++ map (port: {
                        destination = "${p.ip}:${toString port}";
                        proto = "udp";
                        sourcePort = port;
                    })
                    (p.ports.udp or []))
                peers;
            };

            networking.firewall = {
                allowedTCPPorts = allTcpPorts;
                allowedUDPPorts = allUdpPorts;
            };

            # MASQUERADE on tailscale0 so the game server replies back through vps1
            networking.firewall.extraCommands = ''
                iptables -t nat -A POSTROUTING -o tailscale0 -j MASQUERADE
            '';
            networking.firewall.extraStopCommands = ''
                iptables -t nat -D POSTROUTING -o tailscale0 -j MASQUERADE || true
            '';
        };
    };
}
