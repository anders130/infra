{
    serviceRegistry.tautulli = {
        web = {
            subdomain = "tautulli";
            port = 8181;
            local = true;
        };
        dashboard = nixos: {
            name = "Tautulli";
            category = "Media";
            widget = {
                type = "tautulli";
                baseUrl = "http://127.0.0.1:${toString nixos.services.tautulli.port}";
                apiKeyEnvVar = "TAUTULLI_API_KEY";
            };
            widgetSecrets.TAUTULLI_API_KEY = {name = "tautulli/api_key";};
            resourceUnits = ["tautulli.service"];
        };
    };

    den.aspects.tautulli.nixos.services.tautulli.enable = true;
}
