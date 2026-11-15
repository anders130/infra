{den, ...}: {
    serviceRegistry.homebox = {
        web = {
            subdomain = "inventory";
            local = true;
            trustedCert = true;
            port = 7745;
        };
        dashboard = nixos: {
            name = "Homebox";
            description = "Home inventory";
            category = "Personal";
            icon = "homebox";
            widget.type = "link";
            resourceUnits = ["homebox.service"];
        };
        access = {};
    };

    den.aspects.homebox.includes = with den.aspects; [postgres];

    den.aspects.homebox.nixos = {
        config,
        pkgs,
        ...
    }: let
        svc = config.my.services.homebox;
        secretEnvFile = "/run/homebox-secrets.env";
    in {
        my.services.postgres.databases.homebox = {};

        sops.secrets."homebox/auth_api_key_pepper" = {
            sopsFile = config.my.secretFiles.homebox;
            mode = "0400";
        };

        services.homebox = {
            enable = true;
            settings = {
                HBOX_WEB_HOST = "127.0.0.1";
                HBOX_WEB_PORT = toString svc.port;
                HBOX_DATABASE_DRIVER = "postgres";
                HBOX_DATABASE_HOST = "/run/postgresql";
                HBOX_DATABASE_USERNAME = "homebox";
                HBOX_DATABASE_DATABASE = "homebox";
                HBOX_DATABASE_PORT = toString config.services.postgresql.settings.port;
                HBOX_OPTIONS_ALLOW_REGISTRATION = "false";
                HBOX_OPTIONS_TRUST_PROXY = "true";
            };
        };

        systemd.services = {
            homebox-gen-secrets = {
                description = "Generate Homebox secrets env file";
                before = ["homebox.service"];
                requiredBy = ["homebox.service"];
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "+${pkgs.writeShellScript "homebox-gen-secrets" ''
                        set -euo pipefail
                        PEPPER=$(cat ${config.sops.secrets."homebox/auth_api_key_pepper".path})
                        printf 'HBOX_AUTH_API_KEY_PEPPER=%s\n' "$PEPPER" > ${secretEnvFile}
                        chmod 440 ${secretEnvFile}
                        chown homebox:homebox ${secretEnvFile}
                    ''}";
                };
            };

            homebox = {
                bindsTo = ["homebox-gen-secrets.service"];
                after = ["homebox-gen-secrets.service"];
                serviceConfig.EnvironmentFile = [secretEnvFile];
            };
        };
    };
}
