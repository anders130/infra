{lib, ...}: let
    scopes = ["openid" "profile" "email" "groups"];
in {
    serviceRegistry.homebox.oidc = {
        inherit scopes;
        redirectUris = nixos: ["${nixos.my.services.homebox.url}/api/v1/users/login/oidc/callback"];
        clientSettings.token_endpoint_auth_method = "client_secret_basic";
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.homebox.oidc;
            oidcEnvFile = "/run/homebox-oidc.env";
        in {
            systemd.services = {
                homebox-gen-oidc = {
                    description = "Generate Homebox OIDC env";
                    after = ["authelia-main-gen-oidc.service"];
                    requires = ["authelia-main-gen-oidc.service"];
                    before = ["homebox.service"];
                    wantedBy = ["homebox.service"];
                    serviceConfig = {
                        Type = "oneshot";
                        RemainAfterExit = true;
                        ExecStart = "+${pkgs.writeShellScript "homebox-gen-oidc" ''
                            set -euo pipefail
                            SECRET=$(cat ${config.sops.secrets."homebox/oidc_client_secret".path})
                            {
                                printf 'HBOX_OIDC_ENABLED=true\n'
                                printf 'HBOX_OIDC_CLIENT_ID=%s\n' "${cfgOidc.clientId}"
                                printf 'HBOX_OIDC_CLIENT_SECRET=%s\n' "$SECRET"
                                printf 'HBOX_OIDC_ISSUER_URL=%s\n' "${cfgOidc.issuerUrl}"
                                printf 'HBOX_OIDC_SCOPE=%s\n' "${lib.concatStringsSep " " scopes}"
                            } > ${oidcEnvFile}
                            chmod 440 ${oidcEnvFile}
                            chown homebox:homebox ${oidcEnvFile}
                        ''}";
                    };
                };

                homebox = {
                    bindsTo = ["homebox-gen-oidc.service"];
                    after = ["homebox-gen-oidc.service"];
                    serviceConfig.EnvironmentFile = lib.mkAfter [oidcEnvFile];
                };
            };
        };
    };
}
