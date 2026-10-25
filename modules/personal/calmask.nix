{inputs, ...}: {
    flake-file.inputs.calmask.url = "git+ssh://forgejo@git.gollub.dev:2222/jesse/calmask.git";

    serviceRegistry.calmask = {
        web = {
            subdomain = "calmask";
            port = 8097;
            from = "127.0.0.1";
            local = true;
            trustedCert = true;
        };
        oidc = {
            redirectUris = nixos: [
                "${nixos.my.services.calmask.url}/auth/callback"
                "http://127.0.0.1:8765/auth/callback"
            ];
            scopes = ["openid" "profile" "email" "offline_access"];
            clientSettings = {
                grant_types = ["authorization_code" "refresh_token"];
                response_types = ["code"];
                access_token_signed_response_alg = "RS256";
                audience = ["nextcloud"];
                requested_audience_mode = "implicit";
                claims_policy = "calmask";
                lifespan = "calmask";
                require_pkce = true;
                pkce_challenge_method = "S256";
                token_endpoint_auth_method = "client_secret_basic";
            };
            nixos = {config, ...}: let
                cfgOidc = config.my.services.calmask.oidc;
            in {
                services.calmask.oidc = {
                    inherit (cfgOidc) issuerUrl clientId;
                    clientSecretFile = config.sops.secrets."calmask/oidc_client_secret".path;
                };
                systemd.services.calmask = {
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                };
            };
        };
        access = {};
    };

    den.aspects = {
        authelia.nixos.services.authelia.instances.main.settings.identity_providers.oidc = {
            claims_policies.calmask.access_token = ["preferred_username"];
            lifespans.custom.calmask.refresh_token = "30d";
        };

        calmask.nixos = {config, ...}: let
            svc = config.my.services.calmask;
        in {
            imports = [inputs.calmask.nixosModules.calmask];

            sops.secrets."calmask/secret_key".sopsFile = config.my.secretFiles.calmask;

            services.calmask = {
                enable = true;
                listenAddress = config.my.services.caddy.virtualHosts.${svc.fqdn}.from;
                inherit (svc) port;
                publicUrl = svc.url;
                secretKeyFile = config.sops.secrets."calmask/secret_key".path;
                defaultCalDavUrl = "${config.my.services.nextcloud.url}/remote.php/dav";
            };
        };
    };
}
