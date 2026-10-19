{
    config,
    lib,
    ...
}: let
    flake = config;
    managedHosts = lib.filterAttrs (_: host: host.nixos != null) config.hosts;

    sameNetwork = a: b: a._name == b._name;
    sameHost = a: b: a._name == b._name;

    ipOn = host: network: let
        entry = lib.findFirst (i: sameNetwork i.network network) null host.interfaces;
    in
        if entry == null
        then null
        else entry.ip;

    resolveNameservers = nameservers:
        lib.filter (ip: ip != null) (
            map (
                ns:
                    if builtins.isString ns
                    then ns
                    else ipOn ns flake.networks.home
            )
            nameservers
        );

    domainFor = host: let
        participating = lib.filterAttrs (_: d: lib.any (h: sameHost h host) d.hosts) flake.domains;
        owned = lib.filterAttrs (_: d: d.primary != null && sameHost d.primary host) participating;
    in
        if owned != {}
        then lib.head (lib.attrNames owned)
        else if participating != {}
        then lib.head (lib.attrNames participating)
        else null;

    mkProxiedServices = {
        services,
        ip,
        vhostSuffix,
    }: let
        webServices = lib.filterAttrs (_: svc: svc ? port) services;
    in {
        virtualHosts = lib.mapAttrs' (name: svc: {
            name = "http://${name}.${vhostSuffix}";
            value = {
                from = ip;
                inherit (svc) port;
                local = true;
            };
        })
        webServices;
        homepageServices = lib.mapAttrs' (name: svc: {
            name = svc.homepageKey or name;
            value = svc.homepage ip;
        }) (lib.filterAttrs (_: svc: svc ? homepage) webServices);
    };

    mkNfsMounts = {
        ip,
        volumes,
        mountPrefix,
        options ? [],
    }:
        builtins.listToAttrs (map (volume: {
            name = "${mountPrefix}/${lib.toLower volume}";
            value = {
                device = "${ip}:${volume}";
                fsType = "nfs";
                inherit options;
            };
        })
        volumes);

    mkBaseAspect = name: host: {
        nixos = {lib, ...}: let
            ifaces = host.interfaces;

            staticIfaces = lib.filter (i: i.interface != null && i.ip != null && i.network.subnet != "") ifaces;

            prefixOf = network: lib.toInt (builtins.elemAt (lib.splitString "/" network.subnet) 1);

            gatewayEntry = lib.findFirst (i: i.network.gateway != null) null staticIfaces;

            onHomeNetwork = lib.any (i: sameNetwork i.network flake.networks.home) ifaces;

            homeIface = lib.findFirst (i: sameNetwork i.network flake.networks.home) null ifaces;

            nameservers =
                if onHomeNetwork
                then resolveNameservers (flake.networks.home.nameservers or [])
                else [];

            domain = domainFor host;
        in {
            networking.hostName = lib.mkDefault name;
            networking.domain = lib.mkIf (domain != null) (lib.mkDefault domain);

            my.networking.address = lib.mkIf (ipOn host flake.networks.home != null) (lib.mkDefault (ipOn host flake.networks.home));

            my.networking.tailscaleIP = lib.mkIf (ipOn host flake.networks.vpn != null) (lib.mkDefault (ipOn host flake.networks.vpn));

            my.networking.lanInterface = lib.mkIf (homeIface != null && homeIface.interface != null) (lib.mkDefault homeIface.interface);

            networking.defaultGateway = lib.mkIf (gatewayEntry != null) (lib.mkDefault gatewayEntry.network.gateway);

            networking.nameservers = lib.mkIf (nameservers != []) (lib.mkDefault nameservers);

            networking.interfaces = lib.mkIf (staticIfaces != []) (
                lib.listToAttrs (map (i: {
                    name = i.interface;
                    value = {
                        useDHCP = lib.mkDefault false;
                        ipv4.addresses = [
                            {
                                address = i.ip;
                                prefixLength = prefixOf i.network;
                            }
                        ];
                    };
                })
                staticIfaces)
            );
        };
    };
in {
    options = {
        networks = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
                options = {
                    _name = lib.mkOption {
                        type = lib.types.str;
                        default = name;
                        readOnly = true;
                    };
                    subnet = lib.mkOption {
                        type = lib.types.str;
                        default = "";
                    };
                    type = lib.mkOption {
                        type = lib.types.str;
                        default = "ethernet";
                    };
                    gateway = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                    };
                    nameservers = lib.mkOption {
                        type = lib.types.listOf lib.types.raw;
                        default = [];
                    };
                };
            }));
            default = {};
        };

        hosts = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule ({name, ...}: {
                freeformType = lib.types.attrsOf lib.types.anything;
                options = {
                    _name = lib.mkOption {
                        type = lib.types.str;
                        default = name;
                        readOnly = true;
                    };
                    nixos = lib.mkOption {
                        type = lib.types.nullOr lib.types.raw;
                        default = null;
                    };
                    interfaces = lib.mkOption {
                        type = lib.types.listOf (lib.types.submodule {
                            options = {
                                network = lib.mkOption {type = lib.types.raw;};
                                ip = lib.mkOption {
                                    type = lib.types.nullOr lib.types.str;
                                    default = null;
                                };
                                interface = lib.mkOption {
                                    type = lib.types.nullOr lib.types.str;
                                    default = null;
                                };
                            };
                        });
                        default = [];
                    };
                    aspects = lib.mkOption {
                        type = lib.types.listOf lib.types.raw;
                        default = [];
                    };
                    sshHostKey = lib.mkOption {
                        type = lib.types.nullOr lib.types.str;
                        default = null;
                    };
                    nixCache = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                    };
                };
            }));
            default = {};
        };

        domains = lib.mkOption {
            type = lib.types.attrsOf (lib.types.submodule {
                options = {
                    hosts = lib.mkOption {
                        type = lib.types.listOf lib.types.raw;
                        default = [];
                    };
                    primary = lib.mkOption {
                        type = lib.types.nullOr lib.types.raw;
                        default = null;
                    };
                };
            });
            default = {};
        };

        hostsLib = lib.mkOption {
            internal = true;
            readOnly = true;
            type = lib.types.raw;
            default = {inherit ipOn mkProxiedServices mkNfsMounts;};
        };

        hostKeys = lib.mkOption {
            readOnly = true;
            type = lib.types.attrsOf lib.types.str;
            description = "SSH host public key of every host declaring one, keyed by host name.";
            default =
                config.hosts
                |> lib.filterAttrs (_: host: host.sshHostKey != null)
                |> lib.mapAttrs (_: host: host.sshHostKey);
        };

        nixCacheHost = lib.mkOption {
            readOnly = true;
            type = lib.types.nullOr lib.types.raw;
            description = "The host serving the fleet's binary cache, or null if none declares one.";
            default = lib.findFirst (host: host.nixCache) null (lib.attrValues config.hosts);
        };
    };

    config.den.aspects =
        lib.mapAttrs' (name: host: {
            name = "${name}-base";
            value = mkBaseAspect name host;
        })
        managedHosts
        // lib.mapAttrs (name: host: {
            includes = [config.den.aspects."${name}-base"] ++ host.aspects;
        })
        managedHosts;
}
