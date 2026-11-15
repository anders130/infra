{
    serviceRegistry.cockpit = {
        web = {
            subdomain = "cockpit";
            port = 9090;
            local = true;
        };
        dashboard = {
            name = "Cockpit";
            category = "Platform";
        };
    };

    den.aspects.cockpit.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (config.my.services.cockpit) fqdn;
    in {
        systemd.sockets.cockpit.socketConfig = {
            TriggerLimitIntervalSec = "10s";
            TriggerLimitBurst = 200;
        };
        systemd.services."cockpit-wsinstance-socket-user" = {
            startLimitIntervalSec = 10;
            startLimitBurst = 100;
        };

        services.cockpit = {
            enable = true;
            settings.WebService = {
                AllowUnencrypted = true;
                Origins = lib.mkForce "http://${fqdn} ws://${fqdn}";
                ProtocolHeader = "X-Forwarded-Proto";
            };
        };
    };
}
