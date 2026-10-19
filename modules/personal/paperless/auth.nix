{
    serviceRegistry.paperless.oidc = {
        redirectUris = nixos: ["${nixos.my.services.paperless.url}/accounts/oidc/authelia/login/callback/"];
        scopes = ["openid" "profile" "email"];
        clientSettings.token_endpoint_auth_method = "client_secret_basic";
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.paperless.oidc;
            oidcEnvFile = "/run/paperless-oidc.env";
            providerId = "authelia";
        in {
            services.paperless = {
                settings = {
                    PAPERLESS_APPS = "allauth.socialaccount.providers.openid_connect";
                    PAPERLESS_SOCIAL_AUTO_SIGNUP = false;
                    PAPERLESS_SOCIALACCOUNT_ALLOW_SIGNUPS = false;
                    PAPERLESS_DISABLE_REGULAR_LOGIN = true;
                };
                environmentFile = oidcEnvFile;
            };

            systemd.services.paperless-gen-oidc = {
                description = "Generate Paperless OIDC env";
                after = ["authelia-main-gen-oidc.service"];
                requires = ["authelia-main-gen-oidc.service"];
                wantedBy = ["paperless-web.service"];
                before = ["paperless-web.service"];
                serviceConfig = let
                    script = pkgs.writeShellScript "paperless-gen-oidc" ''
                        set -euo pipefail
                        SECRET=$(cat ${config.sops.secrets."paperless/oidc_client_secret".path})
                        PROVIDERS=$(${pkgs.jq}/bin/jq -cn \
                            --arg id "${providerId}" \
                            --arg clientId "${cfgOidc.clientId}" \
                            --arg secret "$SECRET" \
                            --arg serverUrl "${cfgOidc.issuerUrl}/.well-known/openid-configuration" \
                            '{
                                "openid_connect": {
                                    "OAUTH_PKCE_ENABLED": true,
                                    "APPS": [{
                                        "provider_id": $id,
                                        "name": "Authelia",
                                        "client_id": $clientId,
                                        "secret": $secret,
                                        "settings": {
                                            "server_url": $serverUrl,
                                            "token_auth_method": "client_secret_basic"
                                        }
                                    }]
                                }
                            }')
                        printf "PAPERLESS_SOCIALACCOUNT_PROVIDERS='%s'\n" "$PROVIDERS" > "${oidcEnvFile}"
                    '';
                in {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "+${script}";
                };
            };

            systemd.services.paperless-web = {
                bindsTo = ["paperless-gen-oidc.service"];
                after = ["paperless-gen-oidc.service"];
            };
        };
    };
}
