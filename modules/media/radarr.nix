{den, ...}: let
    port = 7878;
in {
    serviceRegistry.radarr = {
        web = {
            subdomain = "radarr";
            local = true;
            inherit port;
            from = nixos: nixos.my.services.mullvad.bridgeAddress;
        };
        dashboard = nixos: {
            name = "Radarr";
            category = "Media";
            visibility = "admin";
            widget = {
                type = "radarr";
                baseUrl = nixos.my.services.radarr.internalUrl;
                apiKeyEnvVar = "RADARR_API_KEY";
            };
            widgetSecrets.RADARR_API_KEY.name = "radarr/api_key";
            resourceUnits = ["radarr.service"];
        };
    };

    den.aspects.radarr.includes = with den.aspects; [mullvad];

    den.aspects.radarr.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.radarr;
    in {
        options.my.services.radarr.libraryDir = mkOption {
            type = types.str;
            default = "/var/lib/radarr/library";
            description = "Movie library root Radarr imports completed downloads into.";
        };

        config = {
            services.radarr = {
                enable = true;
                openFirewall = false;
                settings.server.port = port;
            };

            systemd.services.radarr.vpnConfinement = {
                enable = true;
                vpnNamespace = "mullvad";
            };

            vpnNamespaces.mullvad.portMappings = [
                {
                    from = port;
                    to = port;
                }
            ];

            systemd.tmpfiles.rules = [
                "d ${svc.libraryDir} 0755 ${config.services.radarr.user} ${config.services.radarr.group} -"
            ];
        };
    };
}
