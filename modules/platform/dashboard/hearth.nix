{
    self,
    inputs,
    lib,
    config,
    ...
}: {
    flake-file.inputs.hearth.url = "git+ssh://git@github.com/anders130/hearth?ref=master";

    serviceRegistry.hearth = {
        web = {
            subdomain = "dash2";
            port = 8092;
            local = true;
        };
        oidc = {
            sopsFile = config.secretFiles.dashboard;
            redirectUris = nixos: ["${nixos.my.services.hearth.url}/api/auth/callback"];
            scopes = ["openid" "profile" "email" "groups"];
            clientSettings.token_endpoint_auth_method = "client_secret_post";
            nixos = {config, ...}: let
                cfgOidc = config.my.services.hearth.oidc;
            in {
                systemd.services.hearth.serviceConfig.Environment = [
                    "HEARTH_OIDC_CLIENT_ID=${cfgOidc.clientId}"
                    "HEARTH_OIDC_ISSUER_URL=${cfgOidc.issuerUrl}"
                    "HEARTH_OIDC_REDIRECT_URI=${config.my.services.hearth.url}/api/auth/callback"
                ];
            };
        };
        access = {};
    };

    den.aspects.hearth.nixos = {config, ...}: let
        tagWithHost = hostName:
            lib.mapAttrs (svcKey: svc:
                svc
                // {
                    _host = hostName;
                    _key = svcKey;
                });

        migratedServices =
            self.nixosConfigurations
            |> lib.concatMapAttrs (hostName: hostCfg: hostCfg.config.my.dashboard.services |> tagWithHost hostName)
            |> lib.filterAttrs (_: svc: svc.widget != null);

        mkHearthEntry = svc: {
            inherit (svc) name description category href icon subtitle pollIntervalMs sensitive resourceUnits visibility;
            key = svc._key;
            actions = map (lib.filterAttrs (_: v: v != null)) svc.actions;
            widgetType = svc.widget.type;
            widgetConfig = removeAttrs svc.widget ["type"];
            host =
                if svc.host != null
                then svc.host
                else svc._host;
        };

        hearthServiceEntries = migratedServices |> lib.attrValues |> map mkHearthEntry;

        allWidgetSecrets = migratedServices |> lib.attrValues |> lib.foldl' (acc: svc: acc // svc.widgetSecrets) {};

        hearthHosts =
            [
                {
                    name = config.networking.hostName;
                    metricsUrl = "http://127.0.0.1:9911/metrics";
                }
            ]
            ++ (migratedServices
            |> lib.attrValues
            |> lib.filter (svc: svc.providesHostMetrics)
            |> map (svc: {
                name = svc._key;
                sourceWidgetKey = svc._key;
            }));
    in {
        imports = [inputs.hearth.nixosModules.hearth];
        systemd.settings.Manager.DefaultCPUAccounting = true;
        services.hearth.metricsAgent = {
            enable = true;
            address = "127.0.0.1";
        };
        sops.secrets =
            (allWidgetSecrets
            |> lib.mapAttrs (_: secret: {
                key = secret.name;
                sopsFile =
                    if secret.sopsFile != null
                    then secret.sopsFile
                    else config.my.secretFiles.dashboard;
            }))
            // {"hearth/session_secret".sopsFile = config.my.secretFiles.dashboard;};

        sops.templates."hearth-widget-env".content =
            (allWidgetSecrets |> lib.mapAttrsToList (envVar: _: "${envVar}=${config.sops.placeholder.${envVar}}"))
            ++ [
                "HEARTH_OIDC_CLIENT_SECRET=${config.sops.placeholder."hearth/oidc_client_secret"}"
                "HEARTH_SESSION_SECRET=${config.sops.placeholder."hearth/session_secret"}"
            ]
            |> lib.concatStringsSep "\n";

        services.hearth = {
            enable = true;
            port = config.my.services.hearth.port;
            address = "127.0.0.1";
            environmentFile = config.sops.templates."hearth-widget-env".path;
            actions.enable = true;
            services = hearthServiceEntries;
            hosts = hearthHosts;
            auth = {
                groupRoles.${config.my.services.lldap.adminGroup} = "admin";
                defaultAuthenticatedRole = "user";
            };
        };
        systemd.services.hearth.serviceConfig = {
            Environment = [
                "HEARTH_USERS_PATH=/var/lib/hearth/users.json"
                "HEARTH_PERMISSIONS_ENABLED=true"
            ];
            RestartSec = "5s";
            StateDirectory = "hearth";
        };
    };
}
