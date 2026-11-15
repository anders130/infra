{den, ...}: {
    config.serviceRegistry.authelia = {
        web = {
            subdomain = "auth";
            port = 9091;
        };
        dashboard = {
            name = "Authelia";
            category = "Platform";
        };
    };

    config.den.aspects.authelia.includes = with den.aspects; [lldap access-control];

    config.den.aspects.authelia.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        inherit (config.networking) domain;
        authdomain = config.my.services.authelia.fqdn;
        port = config.my.services.authelia.port;
        instanceName = "main";
        instance = config.services.authelia.instances.${instanceName};
        redisName = "authelia";
        redis = config.services.redis.servers.${redisName};
        redisUnits = ["redis-${redisName}.service"];
        inherit (config.my.services.auth) baseDN;
    in {
        options.my.services.auth.baseDN = mkOption {
            type = types.str;
            readOnly = true;
            default = builtins.concatStringsSep "," (map (p: "dc=${p}") (lib.splitString "." domain));
        };

        config = {
            sops.secrets = lib.genAttrs [
                "authelia/jwt_secret"
                "authelia/session_secret"
                "authelia/storage_key"
                "authelia/oidc_hmac_secret"
                "authelia/oidc_private_key"
                "authelia/smtp_password"
            ] (_: {
                sopsFile = config.my.secretFiles.auth;
                owner = instance.user;
                inherit (instance) group;
            });

            services.authelia.instances.${instanceName} = {
                enable = true;
                secrets = {
                    jwtSecretFile = config.sops.secrets."authelia/jwt_secret".path;
                    sessionSecretFile = config.sops.secrets."authelia/session_secret".path;
                    storageEncryptionKeyFile = config.sops.secrets."authelia/storage_key".path;
                    oidcHmacSecretFile = config.sops.secrets."authelia/oidc_hmac_secret".path;
                    oidcIssuerPrivateKeyFile = config.sops.secrets."authelia/oidc_private_key".path;
                };
                environmentVariables = {
                    AUTHELIA_AUTHENTICATION_BACKEND_LDAP_PASSWORD_FILE =
                        config.sops.secrets."lldap/admin_password".path;
                    AUTHELIA_NOTIFIER_SMTP_PASSWORD_FILE =
                        config.sops.secrets."authelia/smtp_password".path;
                };
                settings = {
                    server.address = "tcp://127.0.0.1:${toString port}/";
                    theme = "auto";
                    log.level = "info";
                    log.format = "text";

                    authentication_backend.ldap = {
                        address = "ldap://127.0.0.1:3890";
                        base_dn = baseDN;
                        user = "uid=admin,ou=people,${baseDN}";
                        attributes = {
                            username = "uid";
                            display_name = "displayName";
                            mail = "mail";
                            group_name = "cn";
                            picture = "avatarUrl";
                        };
                        users_filter = "(&({username_attribute}={input})(objectClass=person))";
                        groups_filter = "(member={dn})";
                    };

                    session = {
                        cookies = [
                            {
                                domain = domain;
                                authelia_url = "https://${authdomain}";
                            }
                        ];
                        redis = {
                            host = redis.unixSocket;
                            port = 0;
                        };
                    };

                    storage.local.path = "/var/lib/authelia-${instanceName}/db.sqlite3";

                    notifier.smtp = {
                        address = "smtp://smtp.strato.de:587";
                        username = "auth@${domain}";
                        sender = "Authelia <auth@${domain}>";
                    };

                    totp.issuer = authdomain;

                    access_control.default_policy = "two_factor";
                };
            };

            services.redis.servers.${redisName} = {
                enable = true;
                inherit (instance) user group;
            };

            systemd.services."authelia-${instanceName}" = {
                after = redisUnits;
                requires = redisUnits;
            };

            my.services.caddy.authAddress = "localhost:${toString port}";
        };
    };
}
