{
    serviceRegistry.audiobookshelf = {
        web = {
            subdomain = "abs";
            port = 8090;
            local = true;
            trustedCert = true;
        };
        dashboard = nixos: {
            name = "Audiobookshelf";
            category = "Media";
            widget = {
                type = "audiobookshelf";
                baseUrl = "http://127.0.0.1:8090";
                tokenEnvVar = "AUDIOBOOKSHELF_TOKEN";
            };
            widgetSecrets.AUDIOBOOKSHELF_TOKEN = {name = "audiobookshelf/api_key";};
            resourceUnits = ["audiobookshelf.service"];
        };
        oidc = {
            redirectUris = nixos: [
                "${nixos.my.services.audiobookshelf.url}/auth/openid/callback"
                "${nixos.my.services.audiobookshelf.url}/auth/openid/mobile-redirect"
            ];
            scopes = ["openid" "profile" "email" "groups"];
            clientSettings.token_endpoint_auth_method = "client_secret_basic";
            nixos = {
                config,
                pkgs,
                ...
            }: let
                cfgOidc = config.my.services.audiobookshelf.oidc;
                db = "/var/lib/audiobookshelf/config/absdatabase.sqlite";
                autoLaunch = "true";
            in {
                systemd.services.audiobookshelf = {
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                    serviceConfig = {
                        LoadCredential = ["oidc_secret:${config.sops.secrets."audiobookshelf/oidc_client_secret".path}"];
                        ExecStartPre = let
                            script = pkgs.writeShellScript "abs-configure-oidc" ''
                                set -euo pipefail
                                DB="${db}"
                                [ ! -f "$DB" ] && exit 0
                                ROW=$(${pkgs.sqlite}/bin/sqlite3 "$DB" "SELECT COUNT(*) FROM settings WHERE key='server-settings';")
                                [ "$ROW" != "1" ] && exit 0

                                SECRET=$(cat "$CREDENTIALS_DIRECTORY/oidc_secret")
                                EMPTY=""
                                ${pkgs.sqlite}/bin/sqlite3 "$DB" "
                                    UPDATE settings SET value = json_set(
                                        value,
                                        '$.authActiveAuthMethods', json('[\"openid\"]'),
                                        '$.authOpenIDIssuerURL', '${cfgOidc.issuerUrl}',
                                        '$.authOpenIDAuthorizationURL', '${cfgOidc.issuerUrl}/api/oidc/authorization',
                                        '$.authOpenIDTokenURL', '${cfgOidc.issuerUrl}/api/oidc/token',
                                        '$.authOpenIDUserInfoURL', '${cfgOidc.issuerUrl}/api/oidc/userinfo',
                                        '$.authOpenIDJwksURL', '${cfgOidc.issuerUrl}/jwks.json',
                                        '$.authOpenIDLogoutURL', '$EMPTY',
                                        '$.authOpenIDClientID', '${cfgOidc.clientId}',
                                        '$.authOpenIDClientSecret', '$SECRET',
                                        '$.authOpenIDTokenSigningAlgorithm', 'RS256',
                                        '$.authOpenIDGroupClaim', '$EMPTY',
                                        '$.authOpenIDAutoRegister', json('true'),
                                        '$.authOpenIDAutoLaunch', json('${autoLaunch}'),
                                        '$.authOpenIDSubfolderForRedirectURLs', '$EMPTY'
                                    ) WHERE key = 'server-settings';
                                "
                            '';
                        in "${script}";
                    };
                };
            };
        };
    };

    den.aspects.audiobookshelf.nixos = {config, ...}: let
        svc = config.my.services.audiobookshelf;
    in {
        services.audiobookshelf = {
            host = "127.0.0.1";
            inherit (svc) port;
            enable = true;
        };

        my.services.caddy.virtualHosts.${svc.fqdn}.extraConfig = ''
            encode gzip zstd
        '';
    };
}
