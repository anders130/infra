{
    den.aspects.caddy.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (builtins) mapAttrs;
        inherit (lib) mkEnableOption mkForce mkOption types;
        cfg = config.my.services.caddy;
    in {
        options.my.services.caddy = {
            authAddress = mkOption {
                type = types.str;
                default = "https://auth.${config.networking.domain}";
                description = "Forward-auth service address. Defaults to the public Authelia URL; override with localhost:9091 if Authelia runs on the same host.";
            };
            virtualHosts = mkOption {
                type = types.attrsOf (types.submodule {
                    options = {
                        from = mkOption {
                            type = types.str;
                            default = "localhost";
                            description = "IP address to proxy from";
                        };
                        port = mkOption {
                            type = types.nullOr types.int;
                            default = null;
                        };
                        extraConfig = mkOption {
                            type = types.lines;
                            default = "";
                        };
                        headers = mkOption {
                            type = types.lines;
                            default = "";
                        };
                        local = mkEnableOption "LAN only. Important for pihole's local domain list.";
                        trustedCert = mkEnableOption "Real publicly-trusted wildcard cert instead of Caddy's self-signed internal CA for a local vhost. Reachability is unaffected -- still LAN-only via pihole.";
                        protect = mkEnableOption "Protect with Authelia forward auth.";
                    };
                });
            };
        };
        config = {
            services.caddy = {
                enable = true;
                virtualHosts = mapAttrs (_: value: {
                    extraConfig = ''
                        ${
                            if value.local && !value.trustedCert
                            then "tls internal"
                            else ""
                        }
                        ${
                            if value.protect
                            then ''
                                forward_auth ${cfg.authAddress} {
                                    uri /api/authz/forward-auth
                                    copy_headers Remote-User Remote-Groups Remote-Email Remote-Name
                                }
                            ''
                            else ""
                        }
                        ${value.extraConfig}
                        ${
                            if value.port != null
                            then ''
                                reverse_proxy ${value.from}:${toString value.port} {
                                    ${value.headers}
                                }
                            ''
                            else ""
                        }
                    '';
                })
                cfg.virtualHosts;
            };
            networking.firewall.allowedTCPPorts = [
                80
                443
            ];
            services.nginx.enable = mkForce false;
        };
    };
}
