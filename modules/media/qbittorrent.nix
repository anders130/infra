{den, ...}: let
    port = 8083;
in {
    serviceRegistry.qbittorrent = {
        web = {
            subdomain = "qbittorrent";
            local = true;
            inherit port;
            from = nixos: nixos.my.services.mullvad.bridgeAddress;
        };
        dashboard = nixos: {
            name = "qBittorrent";
            category = "Media";
            visibility = "admin";
            widget = {
                type = "qbittorrent";
                baseUrl = nixos.my.services.qbittorrent.internalUrl;
                apiKeyEnvVar = "QBITTORRENT_API_KEY";
            };
            widgetSecrets.QBITTORRENT_API_KEY.name = "qbittorrent/api_key";
            resourceUnits = ["qbittorrent.service"];
        };
    };

    den.aspects.qbittorrent.includes = with den.aspects; [mullvad];

    den.aspects.qbittorrent.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.qbittorrent;
    in {
        options.my.services.qbittorrent.downloadsDir = mkOption {
            type = types.str;
            default = "/var/lib/qBittorrent/downloads";
            description = "Where qBittorrent saves downloaded files.";
        };

        config = {
            vpnNamespaces.mullvad.portMappings = [
                {
                    from = port;
                    to = port;
                }
            ];

            systemd.tmpfiles.rules = [
                "d ${svc.downloadsDir} 0755 ${config.services.qbittorrent.user} ${config.services.qbittorrent.group} -"
            ];

            services.qbittorrent = {
                enable = true;
                webuiPort = port;
                openFirewall = false;
                extraArgs = ["--confirm-legal-notice"];
            };

            systemd.services.qbittorrent.vpnConfinement = {
                enable = true;
                vpnNamespace = "mullvad";
            };
        };
    };
}
