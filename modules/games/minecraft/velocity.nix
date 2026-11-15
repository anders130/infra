{
    den.aspects.minecraft.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (builtins) attrNames;
        inherit (lib) mkEnableOption mkMerge mkOption optionalAttrs types;
        cfg = config.my.games.minecraft;

        velocityServers = lib.filterAttrs (_: s: s.enable && !s.directAccess) cfg.servers;

        fabricProxyLiteFor = mcVersion: let
            parts = map lib.toInt (lib.splitString "." mcVersion);
            minor = lib.elemAt parts 1;
            patch =
                if lib.length parts > 2
                then lib.elemAt parts 2
                else 0;
        in
            if minor >= 21 && patch >= 9
            then
                pkgs.fetchurl {
                    url = "https://cdn.modrinth.com/data/8dI2tmqs/versions/nR8AIdvx/FabricProxy-Lite-2.11.0.jar";
                    hash = "sha256-68er6vbAOsYZxwHrszLeaWbG2D7fq/AkNHIMj8PQPNw=";
                }
            else
                pkgs.fetchurl {
                    url = "https://cdn.modrinth.com/data/8dI2tmqs/versions/KqB3UA0q/FabricProxy-Lite-2.10.1.jar";
                    hash = "sha256-NnN7Ysel37Z5rD+san2xD5pCMxf7oZV0vE1HK0cRx0I=";
                };

        viaVersionJar = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/P1OZGk5p/versions/CjleI5xo/ViaVersion-5.11.1-SNAPSHOT.jar";
            hash = "sha256-mSqwbbffbTfB0uP3pF0egFTWzLO7Vscz3TeClp67kAE=";
        };
        viaBackwardsJar = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/NpvuJQoq/versions/djLDmzj6/ViaBackwards-5.11.1-SNAPSHOT.jar";
            hash = "sha256-+Q+bGEgqkWij0marnAxctE3gJB21FvB/PmQU819P2Bs=";
        };

        velocityDataDir = "${cfg.dataDir}/velocity";

        mkVelocityToml = defaultServer: let
            serverLines = lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                    name: srv: ''${name} = "127.0.0.1:${toString srv.server-port}"''
                )
                velocityServers
            );
        in ''
            config-version = "2.7"
            bind = "0.0.0.0:${toString cfg.velocity.port}"
            motd = "${cfg.velocity.motd}"
            show-max-players = 500
            online-mode = true
            force-key-authentication = true
            prevent-client-proxy-connections = false
            player-info-forwarding-mode = "modern"
            announce-forge = false
            kick-existing-players = false

            [servers]
            ${serverLines}

            try = ["${defaultServer}"]

            [forced-hosts]
            ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (
                    host: servers: ''"${host}" = [${lib.concatStringsSep ", " (map (s: "\"${s}\"") servers)}]''
                )
                cfg.velocity.forcedHosts
            )}

            [advanced]
            compression-threshold = 256
            compression-level = -1
            login-ratelimit = 3000
            connection-timeout = 5000
            read-timeout = 30000
            haproxy-protocol = false
            tcp-fast-open = false
            bungee-plugin-message-channel = true
            show-ping-requests = false
            failover-on-unexpected-server-disconnect = true
            announce-proxy-commands = true
            log-command-executions = false
            log-player-connections = true

            [query]
            enabled = false
            port = 25577
            map = "Velocity"
            show-plugins = false
        '';

        velocityConfigs = pkgs.linkFarm "velocity-configs" (
            lib.mapAttrsToList (name: _: {
                name = "${name}.toml";
                path = pkgs.writeText "velocity-${name}.toml" (mkVelocityToml name);
            })
            velocityServers
        );

        velocityAdminScript = pkgs.replaceVars ./velocity-admin.py {
            inherit velocityDataDir;
            servers = lib.toJSON (attrNames velocityServers);
            defaultServer = cfg.velocity.defaultServer;
            adminPort = toString cfg.velocity.adminPort;
        };
    in {
        options.my.games.minecraft.velocity = {
            enable = mkEnableOption "Velocity proxy";
            port = mkOption {
                type = types.port;
                default = 25566;
                description = "Port Velocity listens on (the public-facing port).";
            };
            defaultServer = mkOption {
                type = types.str;
                description = "Server name players connect to by default.";
            };
            motd = mkOption {
                type = types.str;
                default = "Minecraft";
            };
            forwardingSecret = mkOption {
                type = types.str;
                description = "Shared secret for Velocity modern forwarding. Only used on localhost — not exposed externally.";
            };
            forcedHosts = mkOption {
                type = types.attrsOf (types.listOf types.str);
                default = {};
                description = "Map of hostname to server list for Velocity forced-hosts routing. Allows different client versions to connect via different hostnames.";
                example = {"cobblemon.example.com" = ["cobblemon-1-21-1"];};
            };
            adminPort = mkOption {
                type = types.port;
                default = 25580;
                description = "Port for the Velocity admin web UI (binds to 127.0.0.1; proxy with Caddy + basicauth).";
            };
            enableVia = mkEnableOption "ViaVersion + ViaBackwards plugins (cross-version client support). Disabled by default — breaks Fabric modded registry sync.";
        };

        config = lib.mkIf cfg.velocity.enable {
            networking.firewall.allowedTCPPorts = [cfg.velocity.port];

            # Bind backends to localhost only and disable online-mode (only Velocity-proxied servers)
            services.minecraft-servers.servers = lib.mapAttrs (_: v:
                mkMerge [
                    {serverProperties.online-mode = false;}
                    (optionalAttrs (v.type == "fabric") (let
                        jar = fabricProxyLiteFor v.version;
                    in {
                        symlinks = {
                            "mods/${jar.name}" = jar;
                            "config/FabricProxy-Lite.toml" = pkgs.writeText "FabricProxy-Lite.toml" ''
                                secret = "${cfg.velocity.forwardingSecret}"
                                hackEarlyAuth = true
                            '';
                        };
                    }))
                ])
            velocityServers;

            systemd.tmpfiles.rules = ["d ${velocityDataDir} 0750 minecraft minecraft -"];

            systemd.services.minecraft-velocity = {
                description = "Velocity Minecraft proxy";
                wantedBy = ["multi-user.target"];
                after = ["network.target"];
                serviceConfig = {
                    User = "minecraft";
                    Group = "minecraft";
                    WorkingDirectory = velocityDataDir;
                    ExecStartPre = pkgs.writeShellScript "velocity-setup" ''
                        mkdir -p ${velocityDataDir}/{plugins,logs}
                        ${lib.optionalString (!cfg.velocity.enableVia) ''
                            rm -f ${velocityDataDir}/plugins/ViaVersion.jar ${velocityDataDir}/plugins/ViaBackwards.jar
                        ''}
                        ACTIVE=$(cat "${velocityDataDir}/active-server" 2>/dev/null || true)
                        [ -z "$ACTIVE" ] && ACTIVE="${cfg.velocity.defaultServer}"
                        [ ! -f "${velocityConfigs}/$ACTIVE.toml" ] && ACTIVE="${cfg.velocity.defaultServer}"
                        cp -f "${velocityConfigs}/$ACTIVE.toml" "${velocityDataDir}/velocity.toml"
                        printf '%s' ${lib.escapeShellArg cfg.velocity.forwardingSecret} > ${velocityDataDir}/forwarding.secret
                        chmod 600 ${velocityDataDir}/forwarding.secret
                        ${lib.optionalString cfg.velocity.enableVia ''
                            cp -f ${viaVersionJar} ${velocityDataDir}/plugins/ViaVersion.jar
                            cp -f ${viaBackwardsJar} ${velocityDataDir}/plugins/ViaBackwards.jar
                        ''}
                    '';
                    ExecStart = "${pkgs.velocity}/bin/velocity";
                    Restart = "on-failure";
                    RestartSec = "10s";
                };
            };

            # Watch the active-server state file; restart Velocity whenever it changes.
            systemd.paths.minecraft-velocity-config = {
                wantedBy = ["multi-user.target"];
                pathConfig = {
                    PathChanged = "${velocityDataDir}/active-server";
                    Unit = "minecraft-velocity-restart.service";
                };
            };

            systemd.services.minecraft-velocity-restart = {
                description = "Restart Velocity on active-server change";
                serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${pkgs.systemd}/bin/systemctl restart minecraft-velocity.service";
                };
            };

            # Simple admin web UI — pick active server by clicking a button.
            # Serve behind Caddy with basicauth; binds to 127.0.0.1 only.
            systemd.services.minecraft-velocity-admin = {
                description = "Minecraft Velocity admin UI";
                wantedBy = ["multi-user.target"];
                after = ["network.target"];
                serviceConfig = {
                    User = "minecraft";
                    Group = "minecraft";
                    ExecStart = "${pkgs.python3}/bin/python3 ${velocityAdminScript}";
                    Restart = "on-failure";
                    RestartSec = "5s";
                };
            };
        };
    };
}
