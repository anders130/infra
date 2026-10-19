{den, ...}: let
    port = 9696;
in {
    serviceRegistry.prowlarr = {
        web = {
            subdomain = "prowlarr";
            local = true;
            inherit port;
            from = nixos: nixos.my.services.mullvad.bridgeAddress;
        };
        dashboard = nixos: {
            name = "Prowlarr";
            category = "Media";
            visibility = "admin";
            widget = {
                type = "prowlarr";
                baseUrl = nixos.my.services.prowlarr.internalUrl;
                apiKeyEnvVar = "PROWLARR_API_KEY";
            };
            widgetSecrets.PROWLARR_API_KEY.name = "prowlarr/api_key";
            resourceUnits = ["prowlarr.service"];
        };
    };

    den.aspects.prowlarr.includes = with den.aspects; [mullvad];

    den.aspects.prowlarr.nixos = {
        services.prowlarr = {
            enable = true;
            openFirewall = false;
            settings.server.port = port;
        };

        systemd.services.prowlarr.vpnConfinement = {
            enable = true;
            vpnNamespace = "mullvad";
        };

        vpnNamespaces.mullvad.portMappings = [
            {
                from = port;
                to = port;
            }
        ];
    };
}
