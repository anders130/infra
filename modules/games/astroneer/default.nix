{inputs, ...}: {
    serviceRegistry.astroneer = {
        ports.udp = nixos: [nixos.my.games.astroneer.port];
        dashboard = nixos: {
            name = "Astroneer";
            category = "Games";
            widget = {
                type = "custom";
                baseUrl = "${nixos.services.gameStatusHttp.baseUrl}/podman-astroneer";
                mappings = [
                    {
                        path = "status";
                        label = "Status";
                        compact = true;
                        format = "raw";
                    }
                ];
            };
            resourceUnits = ["podman-astroneer.service"];
        };
        actions = [
            {
                id = "start";
                label = "Start";
                unit = "podman-astroneer";
                verb = "start";
            }
            {
                id = "stop";
                label = "Stop";
                unit = "podman-astroneer";
                verb = "stop";
            }
        ];
    };
    den.aspects.astroneer.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        cfg = config.my.games.astroneer;
    in {
        options.my.games.astroneer.port = lib.mkOption {
            type = lib.types.port;
            default = 7777;
        };

        config = {
            my.dashboard.services.astroneer.icon = inputs.hearth.lib.iconFromFile pkgs ./icon.png;

            systemd.tmpfiles.rules = ["d /var/lib/astroneer 0755 admin users - -"];

            virtualisation.oci-containers.containers.astroneer = {
                image = "docker.io/whalybird/astroneer-server:latest";
                autoStart = false;
                ports = ["${toString cfg.port}:7777/udp"];
                volumes = ["/var/lib/astroneer:/astrotux/AstroneerServer/Astro/Saved"];
                # PUBLIC_IP is resolved at startup from the domain since Astroneer doesn't support DNS
                environmentFiles = ["/run/astroneer-public-ip.env"];
                extraOptions = ["--tty" "--interactive"];
            };

            systemd.services."podman-astroneer".serviceConfig.ExecStartPre = pkgs.writeShellScript "astroneer-resolve-ip" ''
                ip=$(${pkgs.dnsutils}/bin/dig +short ${config.networking.domain} | tail -n1)
                echo "PUBLIC_IP=$ip" > /run/astroneer-public-ip.env
                ini=/var/lib/astroneer/Config/WindowsServer/AstroServerSettings.ini
                if [ -f "$ini" ]; then
                    ${pkgs.gnused}/bin/sed -i "s/PublicIP=.*/PublicIP=$ip/" "$ini"
                fi
            '';
        };
    };
}
