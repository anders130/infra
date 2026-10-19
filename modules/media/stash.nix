{
    serviceRegistry.stash = {
        web = {
            subdomain = "stash";
            port = 9999;
            local = true;
            trustedCert = true;
        };
        dashboard = nixos: {
            name = "Stash";
            category = "Media";
            sensitive = true;
            visibility = "admin";
            widget = {
                type = "stash";
                baseUrl = "http://127.0.0.1:${toString nixos.services.stash.settings.port}";
                apiKeyEnvVar = "STASH_API_KEY";
            };
            widgetSecrets.STASH_API_KEY = {name = "stash/api_key";};
            resourceUnits = ["stash.service"];
        };
        actions = [
            {
                id = "scan";
                label = "Scan";
                widgetAction = "scan";
            }
        ];
    };

    den.aspects.stash.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        username = "admin";
        svc = config.my.services.stash;
        folder = svc.dataDir;
    in {
        options.my.services.stash.dataDir = mkOption {
            type = types.str;
            default = "/var/lib/stash";
            description = "Directory Stash stores its config, plugins, and media library under.";
        };

        config.services.stash = {
            inherit username;
            enable = true;
            mutableSettings = true;
            mutablePlugins = true;
            passwordFile = "${folder}/config/password";
            jwtSecretKeyFile = "${folder}/config/jwt";
            sessionStoreKeyFile = "${folder}/config/session";
            settings = {
                stash = [{path = "${folder}/media";}];
                plugins_path = "${folder}/plugins";
            };
        };
    };
}
