{
    serviceRegistry.nextcloud.oidc = {
        redirectUris = nixos: ["${nixos.my.services.nextcloud.url}/apps/oidc_login/oidc"];
        scopes = ["openid" "profile" "email" "groups"];
        clientSettings.token_endpoint_auth_method = "client_secret_basic";
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.nextcloud.oidc;
            secretJsonPath = "/run/nextcloud-oidc-secret.json";
        in {
            services.nextcloud = {
                extraApps = {
                    inherit (pkgs.nextcloud33Packages.apps) oidc_login;
                };
                secretFile = secretJsonPath;
                settings = {
                    oidc_login_provider_url = cfgOidc.issuerUrl;
                    oidc_login_client_id = cfgOidc.clientId;
                    oidc_login_auto_redirect = true;
                    oidc_login_end_session_redirect = false;
                    oidc_login_hide_password_form = true;
                    oidc_login_use_id_token = false;
                    oidc_login_code_challenge_method = "S256";
                    oidc_login_password_authentication = false;
                    oidc_login_webdav_enabled = true;
                    oidc_login_tls_verify = true;
                    oidc_login_scope = "openid profile email groups";
                    oidc_login_attributes = {
                        id = "preferred_username";
                        name = "name";
                        mail = "email";
                    };
                    allow_user_to_change_display_name = false;
                    lost_password_link = "disabled";
                };
            };

            systemd.services = {
                nextcloud-oidc-secret = {
                    description = "Generate Nextcloud OIDC client secret JSON";
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                    before = ["nextcloud-setup.service"];
                    wantedBy = ["nextcloud-setup.service"];
                    serviceConfig = {
                        Type = "oneshot";
                        RemainAfterExit = true;
                        ExecStart = pkgs.writeShellScript "nextcloud-oidc-secret" ''
                            set -euo pipefail
                            SECRET=$(cat ${config.sops.secrets."nextcloud/oidc_client_secret".path})
                            printf '{"oidc_login_client_secret":"%s"}' "$SECRET" > ${secretJsonPath}
                            chmod 440 ${secretJsonPath}
                            chown nextcloud:nextcloud ${secretJsonPath}
                        '';
                    };
                };
                nextcloud-setup = {
                    after = ["nextcloud-oidc-secret.service"];
                    requires = ["nextcloud-oidc-secret.service"];
                };
            };
        };
    };
}
