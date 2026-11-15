{
    serviceRegistry.tandoor.oidc = {
        redirectUris = nixos: ["${nixos.my.services.tandoor.url}/accounts/oidc/authelia/login/callback/"];
        scopes = ["openid" "profile" "email"];
        clientSettings.token_endpoint_auth_method = "client_secret_basic";
        nixos = {
            config,
            lib,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.tandoor.oidc;
            oidcEnvFile = "/run/tandoor-oidc.env";
            providerId = "authelia";
        in {
            services.tandoor-recipes.extraConfig = {
                SOCIALACCOUNT_EMAIL_AUTHENTICATION = 1;
                SOCIALACCOUNT_EMAIL_AUTHENTICATION_AUTO_CONNECT = 1;
                SOCIALACCOUNT_LOGIN_ON_GET = 1;
                HIDE_LOGIN_FORM = 1;
            };

            systemd.services.tandoor-gen-oidc = {
                description = "Generate Tandoor OIDC env";
                after = ["authelia-main-gen-oidc.service"];
                requires = ["authelia-main-gen-oidc.service"];
                wantedBy = ["tandoor-recipes.service"];
                before = ["tandoor-recipes.service"];
                serviceConfig = let
                    script = pkgs.writeShellScript "tandoor-gen-oidc" ''
                        set -euo pipefail
                        SECRET=$(cat ${config.sops.secrets."tandoor/oidc_client_secret".path})
                        PROVIDERS=$(${pkgs.jq}/bin/jq -cn \
                            --arg id "${providerId}" \
                            --arg clientId "${cfgOidc.clientId}" \
                            --arg secret "$SECRET" \
                            --arg serverUrl "${cfgOidc.issuerUrl}/.well-known/openid-configuration" \
                            '{
                                "openid_connect": {
                                    "SCOPE": ["openid","profile","email"],
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
                            }' | ${pkgs.gnused}/bin/sed 's/true/True/g; s/false/False/g')
                        printf 'SOCIAL_PROVIDERS=allauth.socialaccount.providers.openid_connect\n' > "${oidcEnvFile}"
                        printf 'SOCIALACCOUNT_PROVIDERS=%s\n' "$PROVIDERS" >> "${oidcEnvFile}"
                    '';
                in {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "+${script}";
                };
            };

            systemd.services.tandoor-recipes = {
                bindsTo = ["tandoor-gen-oidc.service"];
                after = ["tandoor-gen-oidc.service"];
                serviceConfig.EnvironmentFile = lib.mkAfter [oidcEnvFile];
            };
        };
    };
}
