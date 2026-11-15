{
    serviceRegistry.actual = {
        web = {
            subdomain = "budget";
            port = 5006;
        };
        dashboard = {
            name = "Actual Budget";
            description = "Personal finance";
            category = "Personal";
            widget.type = "link";
            resourceUnits = ["actual.service"];
        };
        access = {};
    };

    den.aspects.actual.nixos = {config, ...}: let
        svc = config.my.services.actual;
    in {
        services.actual = {
            enable = true;
            settings = {
                hostname = "127.0.0.1";
                inherit (svc) port;
                trustedProxies = ["127.0.0.1"];
            };
        };
    };
}
