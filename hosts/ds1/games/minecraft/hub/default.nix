{
    den.aspects.ds1.nixos = {
        pkgs,
        config,
        lib,
        ...
    }: let
        hubRconPort = 25570;

        serverInfos = [
            {
                serverName = "cobblemon-1-21-1";
                displayName = "Cobblemon";
                color = "gold";
                subLine = "Fabric 1.21.1 · 41+ mods";
                motdLine = "Cobblemon 1.6.1 Adventure";
                rconPort = 25571;
            }
            {
                serverName = "five-friends";
                displayName = "Five Friends";
                color = "aqua";
                subLine = "Fabric 1.21.10 · 6 mods";
                motdLine = "5 Freunde – 1 Abenteuer";
                rconPort = 25572;
            }
        ];

        fabricApi1_21_1 = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/P7dR8mSH/versions/aUrTRV7H/fabric-api-0.116.14%2B1.21.1.jar";
            hash = "sha256-Mz8VvOsRegrEHjOW6smHP6bDJcMedG1nmAn5p6AigZY=";
        };
        proxyPortal = pkgs.fetchurl {
            url = "https://cdn.modrinth.com/data/xrUQFGRU/versions/c72cjFcO/ProxyPortal-1.0.5%2B1.21.1.jar";
            sha512 = "801bd6b7add171374d8bbe8638a848817195a09862d0f1d16081da5874d3c41ebce3ecc1e6a4bfa0cbc8d4a1cae3bddba4b35137450cf760970f77e7240399d6";
        };

        hubSpawnDatapack = import ./_datapack.nix {inherit pkgs lib serverInfos;};
        updateCountsScript = import ./_update-counts.nix {inherit pkgs lib serverInfos hubRconPort;};
    in {
        my.games.minecraft.servers.hub = {
            version = "1.21.1";
            type = "fabric";
            server-port = 25569;
            onlyFriends = true;
            autoStart = true;
            motd = "🧱 Gollub Network";
            ram = "1G";
            openFirewall = false;
            notifications = false;
            rcon.enable = true;
            rcon.port = hubRconPort;
            mods = [fabricApi1_21_1 proxyPortal];
            symlinks."world/datapacks/hub-spawn" = hubSpawnDatapack;
        };

        services.minecraft-servers.servers.hub.operators = {
            anders130 = "c2e93d01-d0d9-4e19-95e3-85bf3020b4ef";
        };

        systemd.services.mc-hub-update-counts = {
            description = "Update Minecraft hub portal player counts via RCON";
            after = ["minecraft-server-hub.service"];
            serviceConfig = {
                Type = "oneshot";
                User = "minecraft";
                EnvironmentFile = config.sops.secrets.minecraft.path;
                ExecStart = "${pkgs.python3}/bin/python3 ${updateCountsScript}";
            };
        };
        systemd.timers.mc-hub-update-counts = {
            wantedBy = ["timers.target"];
            timerConfig = {
                OnBootSec = "60s";
                OnUnitActiveSec = "60s";
            };
        };
    };
}
