{
    serviceRegistry.forgejo.oidc = {
        redirectUris = nixos: ["${nixos.my.services.forgejo.url}/user/oauth2/authelia/callback"];
        scopes = ["openid" "profile" "email" "groups"];
        clientSettings.token_endpoint_auth_method = "client_secret_basic";
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfgOidc = config.my.services.forgejo.oidc;
            exe = "${config.services.forgejo.package}/bin/forgejo";
            providerName = "authelia";

            discoveryUrl = "${cfgOidc.issuerUrl}/.well-known/openid-configuration";

            provisionScript = pkgs.writeShellScript "forgejo-gen-oidc" ''
                set -euo pipefail
                SECRET=$(cat "$CREDENTIALS_DIRECTORY/oidc_secret")

                for _ in $(seq 1 15); do
                    curl -sf "${discoveryUrl}" > /dev/null && break
                    sleep 2
                done

                EXISTING_ID=$(${exe} admin auth list | awk -v name="${providerName}" '$2 == name {print $1}' || true)

                if [ -n "$EXISTING_ID" ]; then
                    ${exe} admin auth update-oauth --id "$EXISTING_ID" \
                        --name ${providerName} --provider openidConnect \
                        --key ${cfgOidc.clientId} --secret "$SECRET" \
                        --auto-discover-url ${discoveryUrl} \
                        --scopes "profile email" --allow-username-change
                else
                    ${exe} admin auth add-oauth \
                        --name ${providerName} --provider openidConnect \
                        --key ${cfgOidc.clientId} --secret "$SECRET" \
                        --auto-discover-url ${discoveryUrl} \
                        --scopes "profile email" --allow-username-change
                fi
            '';
        in {
            services.forgejo.settings = {
                service.DISABLE_REGISTRATION = true;
                oauth2_client = {
                    ENABLE_AUTO_REGISTRATION = true;
                    UPDATE_AVATAR = true;
                    USERNAME = "nickname";
                    ACCOUNT_LINKING = "auto";
                };
            };

            systemd.services.forgejo-gen-oidc = {
                description = "Provision Forgejo's Authelia OIDC auth source";
                after = ["forgejo.service" "authelia-main-gen-oidc.service" "authelia-main.service"];
                requires = ["forgejo.service" "authelia-main-gen-oidc.service" "authelia-main.service"];
                wantedBy = ["multi-user.target"];
                path = [pkgs.gawk pkgs.curl];
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    User = config.services.forgejo.user;
                    Group = config.services.forgejo.group;
                    Environment = [
                        "FORGEJO_WORK_DIR=${config.services.forgejo.stateDir}"
                        "FORGEJO_CUSTOM=${config.services.forgejo.customDir}"
                        "HOME=${config.services.forgejo.stateDir}"
                    ];
                    LoadCredential = ["oidc_secret:${config.sops.secrets."forgejo/oidc_client_secret".path}"];
                    ExecStart = provisionScript;
                };
            };
        };
    };
}
