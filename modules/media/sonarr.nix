{den, ...}: let
    port = 8989;
in {
    serviceRegistry.sonarr = {
        web = {
            subdomain = "sonarr";
            local = true;
            inherit port;
            from = nixos: nixos.my.services.mullvad.bridgeAddress;
        };
        dashboard = nixos: {
            name = "Sonarr";
            category = "Media";
            visibility = "admin";
            widget = {
                type = "sonarr";
                baseUrl = nixos.my.services.sonarr.internalUrl;
                apiKeyEnvVar = "SONARR_API_KEY";
            };
            widgetSecrets.SONARR_API_KEY.name = "sonarr/api_key";
            resourceUnits = ["sonarr.service"];
        };
    };

    den.aspects.sonarr.includes = with den.aspects; [mullvad];

    den.aspects.sonarr.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.sonarr;
    in {
        options.my.services.sonarr.libraryDir = mkOption {
            type = types.str;
            default = "/var/lib/sonarr/library";
            description = "TV library root Sonarr imports completed episodes into.";
        };

        config = {
            services.sonarr = {
                enable = true;
                openFirewall = false;
                settings.server.port = port;
            };

            systemd.services.sonarr.vpnConfinement = {
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
                "d ${svc.libraryDir} 0755 ${config.services.sonarr.user} ${config.services.sonarr.group} -"
            ];
        };
    };
}
