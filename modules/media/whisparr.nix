{den, ...}: let
    port = 6969;
in {
    serviceRegistry.whisparr = {
        web = {
            subdomain = "whisparr";
            local = true;
            inherit port;
            from = nixos: nixos.my.services.mullvad.bridgeAddress;
        };
        dashboard = nixos: {
            name = "Whisparr";
            category = "Media";
            sensitive = true;
            visibility = "admin";
            widget = {
                type = "whisparr";
                baseUrl = nixos.my.services.whisparr.internalUrl;
                apiKeyEnvVar = "WHISPARR_API_KEY";
            };
            widgetSecrets.WHISPARR_API_KEY.name = "whisparr/api_key";
            resourceUnits = ["whisparr.service"];
        };
    };

    den.aspects.whisparr.includes = with den.aspects; [mullvad];

    den.aspects.whisparr.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.whisparr;
    in {
        options.my.services.whisparr.libraryDir = mkOption {
            type = types.str;
            default = "/var/lib/whisparr/library";
            description = "Library root Whisparr imports completed downloads into.";
        };

        config = {
            services.whisparr = {
                enable = true;
                openFirewall = false;
                settings.server.port = port;
            };

            systemd.services.whisparr.vpnConfinement = {
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
                "d ${svc.libraryDir} 0755 ${config.services.whisparr.user} ${config.services.whisparr.group} -"
            ];
        };
    };
}
