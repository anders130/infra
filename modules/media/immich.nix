{inputs, ...}: {
    serviceRegistry.immich = {
        web = {
            subdomain = "immich";
            port = 2283;
        };
        dashboard = nixos: {
            name = "Immich";
            description = "Photo library";
            category = "Media";
            widget = {
                type = "immich";
                baseUrl = nixos.my.services.immich.url;
                apiKeyEnvVar = "IMMICH_API_KEY";
            };
            widgetSecrets.IMMICH_API_KEY.name = "immich/api_key";
        };
        oidc = {
            redirectUris = nixos: [
                "${nixos.my.services.immich.url}/auth/login"
                "${nixos.my.services.immich.url}/user-settings"
                "app.immich:///oauth-callback"
            ];
            scopes = ["openid" "profile" "email"];
            clientSettings.token_endpoint_auth_method = "client_secret_post";
            nixos = {config, ...}: let
                cfgOidc = config.my.services.immich.oidc;
                autoLaunch = true;
                autoRegister = true;
            in {
                systemd.services.immich-server = {
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                };

                services.immich.settings = {
                    oauth = {
                        enabled = true;
                        issuerUrl = "${cfgOidc.issuerUrl}/.well-known/openid-configuration";
                        clientId = cfgOidc.clientId;
                        clientSecret._secret = config.sops.secrets."immich/oidc_client_secret".path;
                        scope = "openid profile email";
                        buttonText = "Login with Authelia";
                        inherit autoRegister autoLaunch;
                    };
                    passwordLogin.enabled = false;
                };
            };
        };
        access = {};
    };

    den.aspects.immich.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkForce mkOption types;
        svc = config.my.services.immich;
    in {
        options.my.services.immich = {
            mediaLocation = mkOption {
                type = types.str;
                default = "/var/lib/immich";
                description = "Directory Immich stores its media library under.";
            };
            mediaGroup = mkOption {
                type = types.str;
                default = "immich";
                description = "Group given ownership of mediaLocation. Override to share the library with another service's group.";
            };
        };

        config.nixpkgs.overlays = [(_: prev: {inherit (inputs.unstable.legacyPackages.${prev.stdenv.hostPlatform.system}) immich;})];

        config.services.immich = {
            mediaLocation = svc.mediaLocation;
            group = svc.mediaGroup;
            enable = true;
            host = "0.0.0.0";
            accelerationDevices = ["/dev/dri/renderD128"];
            settings.library.watch.enabled = true;
        };
        config.systemd = {
            services.immich-server.serviceConfig.UMask = mkForce "0027";
            tmpfiles.settings.immich = mkForce {
                ${config.services.immich.mediaLocation}.e = {
                    group = svc.mediaGroup;
                    user = "immich";
                    mode = "0750";
                };
            };
        };
    };
}
