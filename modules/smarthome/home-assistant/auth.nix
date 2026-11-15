{inputs, ...}: {
    serviceRegistry."home-assistant".oidc = {
        clientId = "homeassistant";
        secretName = "home-assistant/oidc_secret";
        redirectUris = nixos: ["${nixos.my.services."home-assistant".url}/auth/oidc/callback"];
        scopes = ["openid" "profile" "groups"];
        clientSettings = {
            token_endpoint_auth_method = "client_secret_post";
        };
        nixos = {
            config,
            pkgs,
            ...
        }: let
            cfg = config.my.services.home-assistant.oidc;
            adminGroup = "admins";
        in {
            services.home-assistant.config.auth_oidc = {
                client_id = cfg.clientId;
                client_secret = "!secret oidc_client_secret";
                discovery_url = "${cfg.issuerUrl}/.well-known/openid-configuration";
                display_name = "Authelia";
                roles.admin = adminGroup;
            };

            nixpkgs.overlays = [
                (_: prev: {
                    inherit (inputs.unstable.legacyPackages.${prev.stdenv.hostPlatform.system}) home-assistant-custom-components;
                })
            ];

            services.home-assistant = {
                customComponents = [pkgs.home-assistant-custom-components.auth_oidc];
                extraPackages = ps: [ps.joserfc];
            };

            systemd.services.hass-gen-oidc-secret = {
                description = "Write Home Assistant OIDC secret from derived key";
                after = ["authelia-main-gen-oidc.service"];
                requires = ["authelia-main-gen-oidc.service"];
                before = ["home-assistant.service"];
                wantedBy = ["home-assistant.service"];
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = pkgs.writeShellScript "hass-gen-oidc-secret" ''
                        set -euo pipefail
                        SECRET=$(cat ${config.sops.secrets."home-assistant/oidc_secret".path})
                        rm -f /var/lib/hass/secrets.yaml
                        printf 'oidc_client_secret: %s\n' "$SECRET" > /var/lib/hass/secrets.yaml
                        chown hass:hass /var/lib/hass/secrets.yaml
                        chmod 600 /var/lib/hass/secrets.yaml
                    '';
                };
            };

            systemd.services.home-assistant = {
                bindsTo = ["hass-gen-oidc-secret.service"];
                after = ["hass-gen-oidc-secret.service"];
            };
        };
    };
}
