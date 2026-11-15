{
    inputs,
    config,
    lib,
    ...
}: let
    inherit (config) hostsLib serviceLib;
in {
    options.hosts = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule {
            options.relay = lib.mkOption {
                type = lib.types.nullOr (lib.types.submodule {
                    options = {
                        from = lib.mkOption {type = lib.types.raw;};
                        services = lib.mkOption {type = lib.types.listOf lib.types.raw;};
                    };
                });
                default = null;
                description = "Forward the services' ports arriving on this host's public interface to `from` over the tailnet.";
            };
        });
    };

    config.den.aspects =
        config.hosts
        |> lib.filterAttrs (_: host: host.nixos != null && host.relay != null)
        |> lib.mapAttrs (_: host: {
            nixos = {config, ...}: let
                inherit (host.relay) from services;
                peer = hostsLib.ipOn from hostsLib.tailnet;
                fromConfig = inputs.self.nixosConfigurations.${from._name}.config;
                portsFor = proto: lib.concatMap (svc: serviceLib.resolveFn fromConfig svc.ports.${proto}) services;
                tcp = portsFor "tcp";
                udp = portsFor "udp";
                forward = proto:
                    map (port: {
                        destination = "${peer}:${toString port}";
                        inherit proto;
                        sourcePort = port;
                    });
                public = lib.findFirst (i: i.network.role == "public") null host.interfaces;
                masquerade = action: suffix:
                    [
                        {
                            proto = "tcp";
                            ports = tcp;
                        }
                        {
                            proto = "udp";
                            ports = udp;
                        }
                    ]
                    |> lib.filter ({ports, ...}: ports != [])
                    |> map ({
                        proto,
                        ports,
                    }: "iptables -t nat ${action} POSTROUTING -o ${config.services.tailscale.interfaceName} -d ${peer} -p ${proto} -m multiport --dports ${lib.concatMapStringsSep "," toString ports} -j MASQUERADE${suffix}")
                    |> lib.concatLines;
            in {
                networking = {
                    nat = {
                        enable = true;
                        externalInterface = public.interface;
                        forwardPorts = forward "tcp" tcp ++ forward "udp" udp;
                    };
                    firewall = {
                        allowedTCPPorts = tcp;
                        allowedUDPPorts = udp;
                        extraCommands = masquerade "-A" "";
                        extraStopCommands = masquerade "-D" " || true";
                    };
                };
            };
        });
}
