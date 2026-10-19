{
    serviceRegistry.matrix.oidc = {
        redirectUris = nixos: ["https://${nixos.my.services.matrix.fqdn}/_synapse/client/oidc/callback"];
        scopes = ["openid" "profile" "email"];
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.matrix.oidc;
            oidcConfigFile = "/run/matrix-synapse-oidc.yaml";
        in {
            systemd.services.matrix-synapse-gen-oidc = {
                description = "Generate Matrix Synapse OIDC config";
                wantedBy = ["matrix-synapse.service"];
                before = ["matrix-synapse.service"];
                serviceConfig = let
                    script = pkgs.writeShellScript "matrix-synapse-gen-oidc" ''
                        set -euo pipefail
                        SECRET=$(cat ${config.sops.secrets."matrix/oidc_client_secret".path})
                        cat > ${oidcConfigFile} <<SYNAPSE_OIDC_EOF
                        oidc_providers:
                          - idp_id: authelia
                            idp_name: Authelia
                            discover: true
                            issuer: "${cfgOidc.issuerUrl}"
                            client_id: "${cfgOidc.clientId}"
                            client_secret: "$SECRET"
                            scopes: ["openid", "profile", "email"]
                            user_profile_method: "userinfo_endpoint"
                            user_mapping_provider:
                              config:
                                localpart_template: "{{ user.preferred_username | lower }}"
                                display_name_template: "{{ user.name }}"
                        SYNAPSE_OIDC_EOF
                        chown root:matrix-synapse ${oidcConfigFile}
                        chmod 640 ${oidcConfigFile}
                    '';
                in {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "+${script}";
                };
            };

            systemd.services.matrix-synapse = {
                bindsTo = ["matrix-synapse-gen-oidc.service"];
                after = ["matrix-synapse-gen-oidc.service"];
            };

            services.matrix-synapse.extraConfigFiles = [oidcConfigFile];
        };
    };
}
