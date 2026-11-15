{den, ...}: {
    serviceRegistry.matrix = {
        web = {
            subdomain = "matrix";
            port = 8008;
        };
        dashboard = {
            name = "Matrix";
            description = "Chat server";
            category = "Personal";
        };
        access = {};
    };

    den.aspects.matrix.includes = with den.aspects; [postgres];

    den.aspects.matrix.nixos = {config, ...}: let
        baseDomain = config.networking.domain;
        inherit (config.my.services.matrix) fqdn port;
        hsSettings = {
            homeserver = {
                address = "http://localhost:${toString port}";
                domain = baseDomain;
            };
            bridge.permissions = {
                "${baseDomain}" = "user";
                "@admin:${baseDomain}" = "admin";
            };
        };
    in {
        sops.secrets."matrix/synapse-secrets" = {
            owner = "matrix-synapse";
            sopsFile = config.my.secretFiles.matrix;
        };

        nixpkgs.config.permittedInsecurePackages = ["olm-3.2.16"];

        services = {
            matrix-synapse = {
                enable = true;
                extras = ["oidc"];
                extraConfigFiles = [
                    config.sops.secrets."matrix/synapse-secrets".path
                ];
                settings = {
                    server_name = baseDomain;
                    public_baseurl = "https://${fqdn}";

                    database = {
                        name = "psycopg2";
                        allow_unsafe_locale = true;
                        args = {
                            user = "matrix-synapse";
                            database = "matrix-synapse";
                            host = "/run/postgresql";
                        };
                    };

                    listeners = [
                        {
                            inherit port;
                            bind_addresses = ["127.0.0.1"];
                            type = "http";
                            tls = false;
                            x_forwarded = true;
                            resources = [
                                {
                                    names = ["client" "federation"];
                                    compress = true;
                                }
                            ];
                        }
                    ];

                    enable_registration = false;
                    enable_registration_without_verification = false;
                    suppress_key_server_warning = true;
                    url_preview_enabled = true;
                    max_upload_size = "50M";
                };
            };

            mautrix-signal = {
                enable = true;
                registerToSynapse = true;
                settings = hsSettings;
            };

            mautrix-whatsapp = {
                enable = true;
                registerToSynapse = true;
                settings = hsSettings;
            };
        };

        my.services.postgres.databases.matrix-synapse = {};

        my.services.caddy.virtualHosts.${fqdn}.headers = ''
            header_down Access-Control-Allow-Origin "*"
            header_down Access-Control-Allow-Methods "GET, POST, PUT, DELETE, OPTIONS"
            header_down Access-Control-Allow-Headers "Origin, X-Requested-With, Content-Type, Accept, Authorization"
        '';
    };
}
