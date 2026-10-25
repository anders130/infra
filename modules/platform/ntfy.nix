{inputs, ...}: {
    serviceRegistry.ntfy = {
        web = {
            subdomain = "ntfy";
            port = 2586;
        };
        dashboard = {
            name = "ntfy";
            description = "Push notifications";
            category = "Platform";
        };
    };

    den.aspects.ntfy.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (builtins) attrNames;
        inherit (lib) mapAttrsToList mkMerge mkOption types;

        ntfySvc = config.my.services.ntfy;
        inherit (ntfySvc) port;

        ntfyUrl = config.services.ntfy-sh.settings.base-url;
        message = pkgs.writeShellScriptBin "message" ''
            curl -fsS -u "$NTFY_TOPIC:$NTFY_PASS" -d "$1" ${ntfyUrl}/$NTFY_TOPIC
        '';
        scriptDeps = with pkgs; [
            curl
            coreutils
            message
        ];
        mkSystemdService = cfg: name: source: {
            "notify-${name}" = {
                description = "Notifications for ${name}";
                inherit (source) wantedBy after partOf;
                serviceConfig = {
                    User = source.user;
                    Group = source.group;
                    ExecStart = lib.getExe (source.script scriptDeps);
                    Restart = "on-failure";
                    EnvironmentFile = cfg.targets.${source.target}.secretFile;
                    Environment = "NTFY_TOPIC=${cfg.targets.${source.target}.topic}";
                };
            };
        };
        cfg = config.my.services.ntfy;
    in {
        options.my.services.ntfy = {
            targets = mkOption {
                type = types.attrsOf (types.submodule ({name, ...}: {
                    options = {
                        topic = mkOption {
                            type = types.str;
                            default = name;
                        };
                        secretFile = mkOption {
                            type = types.path;
                            description = "Secret .env file for the app that contains the `NTFY_PASS` environment variable";
                        };
                        authHash = mkOption {
                            type = types.str;
                            description = "Hashed password for the app. Optain with `ntfy user hash`";
                        };
                    };
                }));
                default = {};
            };
            sources = mkOption {
                type = types.attrsOf (types.submodule ({name, ...}: {
                    options = {
                        target = mkOption {
                            type = types.str;
                            description = "Name of the target to send notifications to";
                            default = name;
                        };
                        wantedBy = mkOption {
                            type = types.listOf types.str;
                        };
                        after = mkOption {
                            type = types.listOf types.str;
                        };
                        partOf = mkOption {
                            type = types.listOf types.str;
                        };
                        user = mkOption {
                            type = types.str;
                        };
                        group = mkOption {
                            type = types.str;
                        };
                        script = mkOption {
                            type = types.functionTo types.package;
                            description = "Function that takes the default dependencies as argument and returns a package";
                        };
                    };
                }));
                default = {};
            };
        };
        config = {
            nixpkgs.overlays = [(_: prev: {inherit (inputs.unstable.legacyPackages.${prev.stdenv.hostPlatform.system}) ntfy-sh;})];
            services.ntfy-sh = {
                enable = true;
                settings = {
                    auth-default-access = "deny-all";
                    base-url = ntfySvc.url;
                    listen-http = ":${toString port}";
                    behind-proxy = true;
                    auth-users =
                        ["jesse:$2b$10$TwMEIAZEXN69R.L5e3/a7u.L/3Qo92UwWFYhRT.USF1TwtsyvAeOy:admin"]
                        ++ (mapAttrsToList (name: value: "${name}:${value.authHash}:user") cfg.targets);
                    auth-access = map (name: "${name}:${name}:wo") (attrNames cfg.targets);
                    enable-login = true;
                };
            };
            systemd.services = mkMerge (mapAttrsToList (mkSystemdService cfg) cfg.sources);
            my.services.caddy.virtualHosts.${ntfySvc.fqdn}.extraConfig = ''
                @httpget {
                    protocol http
                    method GET
                    path_regexp ^/([-_a-z0-9]{0,64}$|docs/|static/)
                }
                redir @httpget https://{host}{uri}
            '';
        };
    };
}
