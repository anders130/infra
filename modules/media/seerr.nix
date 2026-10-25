{
    serviceRegistry.seerr = {
        web = {
            subdomain = "seerr";
            port = 5055;
            local = true;
            trustedCert = true;
        };
        dashboard = nixos: {
            name = "Seerr";
            category = "Media";
            widget = {
                type = "seerr";
                baseUrl = "http://127.0.0.1:${toString nixos.services.seerr.port}";
                apiKeyEnvVar = "SEERR_API_KEY";
            };
            widgetSecrets.SEERR_API_KEY.name = "seerr/api_key";
            resourceUnits = ["seerr.service"];
        };
    };

    den.aspects.seerr.nixos.services.seerr.enable = true;
}
