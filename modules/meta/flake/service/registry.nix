{
    config,
    lib,
    ...
}: let
    inherit (lib) mkOption types;

    deferred = t: types.either (types.functionTo t) t;

    webType = types.submodule {
        options = {
            subdomain = mkOption {type = types.str;};
            port = mkOption {
                type = types.nullOr types.port;
                default = null;
            };
            from = mkOption {
                type = deferred types.str;
                default = "localhost";
            };
            local = mkOption {
                type = types.bool;
                default = false;
            };
            trustedCert = mkOption {
                type = types.bool;
                default = false;
            };
            protect = mkOption {
                type = types.bool;
                default = false;
            };
            aliases = mkOption {
                type = types.listOf types.str;
                default = [];
            };
        };
    };

    oidcType = name:
        types.submodule {
            options = {
                clientId = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                };
                secretName = mkOption {
                    type = types.nullOr types.str;
                    default = null;
                };
                sopsFile = mkOption {
                    type = types.path;
                    default = config.secretFiles.${name};
                };
                redirectUris = mkOption {
                    type = deferred (types.listOf types.str);
                    default = [];
                };
                scopes = mkOption {
                    type = types.listOf types.str;
                    default = ["openid" "profile" "email" "groups"];
                };
                clientSettings = mkOption {
                    type = types.attrsOf types.anything;
                    default = {};
                };
                nixos = mkOption {
                    type = types.nullOr types.raw;
                    default = null;
                };
                autoEnable = mkOption {
                    type = types.bool;
                    default = true;
                };
            };
        };

    portsType = types.submodule {
        options = {
            tcp = mkOption {
                type = deferred (types.listOf types.port);
                default = [];
            };
            udp = mkOption {
                type = deferred (types.listOf types.port);
                default = [];
            };
        };
    };

    accessType = types.submodule {
        freeformType = types.attrsOf types.anything;
        options = {
            allow = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
            };
            admin = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
            };
            oneFactorResources = mkOption {
                type = types.listOf types.str;
                default = [];
            };
            bypassResources = mkOption {
                type = types.listOf types.str;
                default = [];
            };
        };
    };

    sopsType = types.submodule {
        options = {
            dotenv = mkOption {
                type = types.bool;
                default = false;
            };
        };
    };

    serviceType = types.submodule ({name, ...}: {
        options = {
            web = mkOption {
                type = types.nullOr webType;
                default = null;
            };
            dashboard = mkOption {
                type = types.nullOr (deferred (types.attrsOf types.anything));
                default = null;
            };
            oidc = mkOption {
                type = types.nullOr (oidcType name);
                default = null;
            };
            ports = mkOption {
                type = portsType;
                default = {};
            };
            actions = mkOption {
                type = deferred (types.listOf types.anything);
                default = [];
            };
            access = mkOption {
                type = types.nullOr accessType;
                default = null;
            };
            sops = mkOption {
                type = types.nullOr sopsType;
                default = null;
            };
        };
    });
in {
    config.den.reservedKeys = ["service"];

    options.serviceRegistry = mkOption {
        type = types.attrsOf serviceType;
        default = {};
    };

    options.serviceLib = mkOption {
        internal = true;
        readOnly = true;
        type = types.raw;
        default = {
            resolveFn = nixosConfig: raw:
                if lib.isFunction raw
                then raw nixosConfig
                else raw;
        };
    };

    config.den.aspects = lib.mapAttrs (_: svc: {service = svc;}) config.serviceRegistry;
}
