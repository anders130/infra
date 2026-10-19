{inputs, ...}: let
    port = 7778;
in {
    serviceRegistry.terraria = {
        ports.tcp = [port];
        dashboard = nixos: {
            name = "Terraria";
            category = "Games";
            widget = {
                type = "game-server";
                kind = "terraria";
                statusUrl = "${nixos.services.gameStatusHttp.baseUrl}/terraria";
                playersMax = 8;
            };
            resourceUnits = ["terraria.service"];
        };
        actions = [
            {
                id = "start";
                label = "Start";
                unit = "terraria";
                verb = "start";
            }
            {
                id = "stop";
                label = "Stop";
                unit = "terraria";
                verb = "stop";
            }
        ];
    };

    den.aspects.terraria.nixos = {lib, ...}: {
        nixpkgs.overlays = [
            (_: prev: {
                inherit
                    (import inputs.unstable {
                        inherit (prev.stdenv.hostPlatform) system;
                        config.allowUnfree = true;
                    })
                    terraria-server
                    ;
            })
        ];
        services.terraria = {
            inherit port;
            enable = true;
            openFirewall = true;
            worldPath = "/var/lib/terraria/Worlds/Terraria.wld";
            autoCreatedWorldSize = "large";
            maxPlayers = 8;
        };
        systemd.services.terraria.wantedBy = lib.mkForce [];
    };
}
