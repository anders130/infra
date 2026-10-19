{
    config,
    lib,
    ...
}: let
    inherit (config) serviceLib;
in {
    config.den.aspects = lib.mapAttrs (name: svc: {
        nixos = {
            config,
            lib,
            ...
        }: let
            web = svc.web;
            localScoped = web.local;
            trustedLocal = localScoped && web.trustedCert;
            bareHttp = localScoped && !trustedLocal;
            webFrom = serviceLib.resolveFn config web.from;
            webHost =
                if bareHttp
                then config.networking.hostName
                else config.networking.domain;
            fqdn = "${web.subdomain}.${webHost}";
            url = "${
                if bareHttp
                then "http"
                else "https"
            }://${fqdn}";
            vhostKey =
                if bareHttp
                then url
                else fqdn;
        in {
            options = lib.optionalAttrs (web != null) {
                my.services.${name} =
                    {
                        fqdn = lib.mkOption {
                            type = lib.types.str;
                            default = fqdn;
                        };
                        url = lib.mkOption {
                            type = lib.types.str;
                            default = url;
                        };
                    }
                    // lib.optionalAttrs (web.port != null) {
                        port = lib.mkOption {
                            type = lib.types.port;
                            default = web.port;
                        };
                        internalUrl = lib.mkOption {
                            type = lib.types.str;
                            default = "http://${webFrom}:${toString web.port}";
                            description = "Address to reach the service directly, bypassing Caddy -- e.g. for dashboard widgets. Uses web.from (defaults to localhost).";
                        };
                    };
            };

            config = lib.optionalAttrs (web != null && web.port != null) {
                my.services.caddy.virtualHosts = let
                    vhost = {
                        port = web.port;
                        from = webFrom;
                        local = localScoped;
                        trustedCert = trustedLocal;
                        protect = web.protect;
                    };
                    aliasKey = alias:
                        if bareHttp
                        then "http://${alias}"
                        else alias;
                in
                    {${vhostKey} = vhost;}
                    // lib.listToAttrs (map (alias: {
                        name = aliasKey alias;
                        value = vhost;
                    })
                    web.aliases);
            };
        };
    })
    config.serviceRegistry;
}
