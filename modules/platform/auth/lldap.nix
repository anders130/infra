{
    serviceRegistry.lldap = {
        web = {
            subdomain = "ldap";
            port = 17170;
        };
        dashboard = {
            name = "LLDAP";
            category = "Platform";
        };
    };
    den.aspects.lldap.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (config.networking) domain;
        inherit (config.my.services.auth) baseDN;
        svc = config.my.services.lldap;
    in {
        options.my.services.lldap.adminGroup = lib.mkOption {
            type = lib.types.str;
            default = "lldap_admin";
            description = ''
                LLDAP's own bootstrap admin group name -- this is a fact about
                the lldap software itself, not a free choice; it isn't exposed
                as a `services.lldap.settings` option upstream. Named here so
                consumers (e.g. hearth.nix's `auth.groupRoles`) reference this
                option instead of repeating the literal string.
            '';
        };

        config = {
            sops.secrets."lldap/admin_password" = {
                sopsFile = config.my.secretFiles.auth;
                mode = "0444";
            };

            services.lldap = {
                enable = true;
                silenceForceUserPassResetWarning = true;
                environment.LLDAP_LDAP_USER_PASS_FILE =
                    config.sops.secrets."lldap/admin_password".path;
                settings = {
                    ldap_host = "127.0.0.1";
                    http_host = "127.0.0.1";
                    http_port = svc.port;
                    http_url = svc.url;
                    ldap_base_dn = baseDN;
                    ldap_user_email = "admin@${domain}";
                };
            };
        };
    };
}
