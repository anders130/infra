{den, ...}: {
    serviceRegistry.forgejo = {
        web = {
            subdomain = "git";
            local = true;
            trustedCert = true;
            port = 3050;
        };
        dashboard = nixos: {
            name = "Forgejo";
            description = "Git remote";
            category = "Platform";
            widget = {
                type = "forgejo";
                baseUrl = nixos.my.services.forgejo.internalUrl;
                apiKeyEnvVar = "FORGEJO_API_KEY";
            };
            widgetSecrets.FORGEJO_API_KEY.name = "forgejo/api_key";
            resourceUnits = ["forgejo.service"];
        };
    };

    den.aspects.forgejo.includes = with den.aspects; [postgres];

    den.aspects.forgejo.nixos = {
        config,
        lib,
        ...
    }: let
        svc = config.my.services.forgejo;
    in {
        options.my.services.forgejo.sshPort = lib.mkOption {
            type = lib.types.port;
            default = 2222;
        };

        options.my.services.forgejo.sshHostKey = lib.mkOption {
            type = lib.types.str;
        };

        config.networking.firewall.allowedTCPPorts = [svc.sshPort];

        config.services.forgejo = {
            enable = true;
            database.type = "postgres";
            settings.server = {
                DOMAIN = svc.fqdn;
                ROOT_URL = "${svc.url}/";
                HTTP_ADDR = "127.0.0.1";
                HTTP_PORT = svc.port;
                START_SSH_SERVER = true;
                SSH_LISTEN_PORT = svc.sshPort;
                SSH_PORT = svc.sshPort;
            };
        };
    };
}
