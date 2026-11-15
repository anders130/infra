{...}: let
    port = 1883;
in {
    serviceRegistry.mosquitto.ports.tcp = [port];

    den.aspects.mosquitto.nixos = {
        services.mosquitto = {
            enable = true;
            listeners = [
                {
                    inherit port;
                    address = "0.0.0.0";
                    omitPasswordAuth = true;
                    settings.allow_anonymous = true;
                    acl = ["topic readwrite #"];
                }
            ];
        };
    };
}
