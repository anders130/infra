{
    config,
    inputs,
    ...
}: let
    inherit (config) serviceRegistry;
in {
    config.den.aspects.authelia.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        instanceName = "main";
        instance = config.services.authelia.instances.${instanceName};
        cfg = config.my.services.auth;
        oidcClientsYaml = "/run/authelia-${instanceName}-oidc-clients.yaml";

        allHostConfigs = lib.mapAttrsToList (_: hostCfg: hostCfg.config) inputs.self.nixosConfigurations;
        hostConfigFor = svcName: let
            match = lib.findFirst (c: (c.my.services or {}) ? ${svcName}) null allHostConfigs;
        in
            if match == null
            then throw "authelia: no host declares my.services.${svcName}"
            else match;

        oidcServices = lib.filterAttrs (_: svc: svc.oidc != null) serviceRegistry;

        oidcClientEntries = lib.mapAttrs (name: svc: let
            oidc = svc.oidc;
            raw = oidc.redirectUris;
        in {
            clientId =
                if oidc.clientId != null
                then oidc.clientId
                else name;
            secretName =
                if oidc.secretName != null
                then oidc.secretName
                else "${name}/oidc_client_secret";
            inherit (oidc) sopsFile;
            coLocated = config.my.services ? ${name};
            redirectUris =
                if lib.isFunction raw
                then raw (hostConfigFor name)
                else raw;
            inherit (oidc) scopes clientSettings;
            hasAccessControl = svc.access != null;
            authorizationPolicy =
                if svc.access != null
                then "policy-${name}"
                else "two_factor";
        })
        oidcServices;

        remoteOidcClientEntries = lib.filterAttrs (_: entry: !entry.coLocated) oidcClientEntries;

        genOidcClientsScript = pkgs.writeShellScript "authelia-gen-oidc-clients" ''
            set -euo pipefail

            CLIENTS='[]'
            ${builtins.concatStringsSep "\n" (lib.mapAttrsToList (name: client: ''
                {
                    SECRET=$(cat ${toString client.secretFile})
                    # Plaintext client secrets are deprecated in Authelia; hash instead
                    # (the app's own secret value is unchanged, only how Authelia stores it).
                    HASHED_SECRET=$(${pkgs.authelia}/bin/authelia crypto hash generate pbkdf2 \
                        --variant sha512 --password "$SECRET" --no-confirm \
                        | grep -oE '\$pbkdf2-sha512\$\S+')
                    CLIENTS=$(echo "$CLIENTS" | ${pkgs.jq}/bin/jq \
                        --arg id "${name}" \
                        --arg secret "$HASHED_SECRET" \
                        --argjson uris '${builtins.toJSON client.redirectUris}' \
                        --argjson scopes '${builtins.toJSON client.scopes}' \
                        --argjson extra '${builtins.toJSON client.clientSettings}' \
                        --arg authPolicy "${client.authorizationPolicy}" \
                        '. + [({
                            "client_id": $id,
                            "client_secret": $secret,
                            "redirect_uris": $uris,
                            "scopes": $scopes,
                            "grant_types": ["authorization_code"],
                            "response_types": ["code"],
                            "consent_mode": "implicit",
                            "authorization_policy": $authPolicy
                        } + $extra)]')
                }
            '')
            cfg.oidcClients)}

            echo "$CLIENTS" | ${pkgs.jq}/bin/jq \
                '{identity_providers: {oidc: {clients: .}}}' > "${oidcClientsYaml}"
        '';
    in {
        options.my.services.auth.oidcClients = lib.mkOption {
            default = {};
            type = lib.types.attrsOf (lib.types.submodule {
                options = {
                    redirectUris = lib.mkOption {type = lib.types.listOf lib.types.str;};
                    postLogoutRedirectUris = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = [];
                    };
                    scopes = lib.mkOption {
                        type = lib.types.listOf lib.types.str;
                        default = ["openid" "profile" "email" "groups"];
                    };
                    clientSettings = lib.mkOption {
                        type = lib.types.attrs;
                        default = {};
                    };
                    secretFile = lib.mkOption {type = lib.types.path;};
                    hasAccessControl = lib.mkOption {
                        type = lib.types.bool;
                        default = false;
                    };
                    authorizationPolicy = lib.mkOption {
                        type = lib.types.str;
                        default = "two_factor";
                        description = "Named policy ID, e.g. \"policy-<serviceRegistry-name>\". Not derived from this submodule's own attribute name -- oidcClients is keyed by clientId, which can differ from the serviceRegistry name (e.g. home-assistant/homeassistant). Callers with access control must set this explicitly.";
                    };
                };
            });
        };

        config = {
            sops.secrets = lib.mapAttrs' (_: entry: {
                name = entry.secretName;
                value = {
                    sopsFile = entry.sopsFile;
                    owner = instance.user;
                    inherit (instance) group;
                };
            })
            remoteOidcClientEntries;

            my.services.auth.oidcClients = lib.mapAttrs' (_: entry: {
                name = entry.clientId;
                value = {
                    inherit (entry) redirectUris scopes clientSettings hasAccessControl authorizationPolicy;
                    secretFile = config.sops.secrets.${entry.secretName}.path;
                };
            })
            oidcClientEntries;

            systemd.services."authelia-${instanceName}-gen-oidc" = lib.mkIf (cfg.oidcClients != {}) {
                description = "Generate Authelia OIDC clients config";
                wantedBy = ["authelia-${instanceName}.service"];
                before = ["authelia-${instanceName}.service"];
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "+${genOidcClientsScript}";
                };
            };

            systemd.services."authelia-${instanceName}" = lib.mkIf (cfg.oidcClients != {}) {
                bindsTo = ["authelia-${instanceName}-gen-oidc.service"];
                after = ["authelia-${instanceName}-gen-oidc.service"];
            };

            services.authelia.instances.${instanceName}.settingsFiles =
                lib.mkIf (cfg.oidcClients != {}) [oidcClientsYaml];
        };
    };
}
