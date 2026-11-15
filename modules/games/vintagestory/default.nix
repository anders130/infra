{
    serviceRegistry.vintagestory = {
        ports = {
            tcp = nixos: [nixos.my.games.vintagestory.port];
            udp = nixos: [nixos.my.games.vintagestory.port];
        };
        sops.dotenv = true;
        dashboard = nixos: {
            name = "Vintage Story";
            icon = "https://media.vintagestory.at/monthly_2019_07/android-chrome-256x256.png";
            category = "Games";
            widget = {
                type = "custom";
                baseUrl = "${nixos.services.gameStatusHttp.baseUrl}/vintagestory";
                mappings = [
                    {
                        path = "status";
                        label = "Status";
                        compact = true;
                        format = "raw";
                    }
                ];
            };
            resourceUnits = ["vintagestory.service"];
        };
        actions = [
            {
                id = "start";
                label = "Start";
                unit = "vintagestory";
                verb = "start";
            }
            {
                id = "stop";
                label = "Stop";
                unit = "vintagestory";
                verb = "stop";
            }
        ];
    };

    den.aspects.vintagestory.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        cfg = config.my.games.vintagestory;
        package = pkgs.callPackage ./_package.nix {};
        dataDir = "/var/lib/vintagestory";
        settings = {
            ServerName = cfg.name;
            Port = cfg.port;
            WhitelistMode = 1;
        };
        configure = pkgs.writeShellApplication {
            name = "vintagestory-configure";
            runtimeInputs = [package pkgs.coreutils pkgs.jq];
            text = ''
                [ -f serverconfig.json ] || VintagestoryServer --dataPath ${dataDir} --genconfig
                jq --argjson settings ${lib.escapeShellArg (builtins.toJSON settings)} \
                    '. + $settings + {Password: env.VS_PASSWORD}' serverconfig.json > serverconfig.json.tmp
                mv serverconfig.json.tmp serverconfig.json
            '';
        };
    in {
        options.my.games.vintagestory = {
            port = lib.mkOption {
                type = lib.types.port;
                default = 42420;
            };
            name = lib.mkOption {
                type = lib.types.str;
                default = "Vintage Story Server";
            };
        };

        config = {
            users = {
                users.vintagestory = {
                    isSystemUser = true;
                    group = "vintagestory";
                    home = dataDir;
                };
                groups.vintagestory = {};
            };

            systemd.services.vintagestory = {
                description = "Vintage Story Server";
                wants = ["network-online.target"];
                after = ["network-online.target"];
                serviceConfig = {
                    ExecStartPre = lib.getExe configure;
                    ExecStart = "${lib.getExe package} --dataPath ${dataDir}";
                    EnvironmentFile = config.sops.secrets.vintagestory.path;
                    Restart = "on-failure";
                    RestartSec = "10s";
                    User = "vintagestory";
                    Group = "vintagestory";
                    StateDirectory = "vintagestory";
                    WorkingDirectory = dataDir;

                    CapabilityBoundingSet = [""];
                    DeviceAllow = [""];
                    LockPersonality = true;
                    NoNewPrivileges = true;
                    PrivateDevices = true;
                    PrivateTmp = true;
                    PrivateUsers = true;
                    ProtectClock = true;
                    ProtectControlGroups = true;
                    ProtectHome = true;
                    ProtectHostname = true;
                    ProtectKernelLogs = true;
                    ProtectKernelModules = true;
                    ProtectKernelTunables = true;
                    ProtectProc = "invisible";
                    ProtectSystem = "strict";
                    RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX" "AF_NETLINK"];
                    RestrictNamespaces = true;
                    RestrictRealtime = true;
                    RestrictSUIDSGID = true;
                    SystemCallArchitectures = "native";
                    UMask = "0077";
                };
            };
        };
    };
}
