{inputs, ...}: {
    serviceRegistry.jellyfin = {
        web = {
            subdomain = "jellyfin";
            port = 8096;
        };
        dashboard = {
            name = "Jellyfin";
            description = "Media server";
            category = "Media";
            icon = "jellyfin";
            widget = {
                type = "jellyfin";
                baseUrl = "http://127.0.0.1:8096";
                apiKeyEnvVar = "JELLYFIN_API_KEY";
            };
            widgetSecrets.JELLYFIN_API_KEY.name = "jellyfin/api_key";
            resourceUnits = ["jellyfin.service"];
        };
    };

    den.aspects.jellyfin.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.jellyfin;
    in {
        options.my.services.jellyfin.systemUser = mkOption {
            type = types.str;
            default = "jellyfin";
            description = "User account Jellyfin runs as. Override to share ownership with an existing media library user.";
        };

        config.services.jellyfin = {
            enable = true;
            package = inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.jellyfin;
            openFirewall = true;
            user = svc.systemUser;
        };
    };
}
