{inputs, ...}: {
    flake-file = {
        nixConfig = {
            extra-substituters = ["https://anders130.cachix.org"];
            extra-trusted-public-keys = ["anders130.cachix.org-1:mCAq0L6Ld3lG7gxJVHGzKr2rqUZ5qs5YoERxoSjMOXs="];
        };
        inputs.lumehub.url = "github:LumeHub/server/dev";
    };
    flake-follows.exclude = ["lumehub/nixpkgs"];
    den.aspects.led-pi.nixos = {
        imports = [inputs.lumehub.nixosModules.default];

        services.lumehub = {
            enable = true;
            openFirewall = true;
            settings = {
                led_controller.controller_type = "ws2801";
                led_controller.pixel_count = 256;
                mqtt = {
                    enabled = true;
                    host = inputs.self.nixosConfigurations.dns-pi.config.my.networking.address;
                    ha_discovery = true;
                    ha_discovery_prefix = "homeassistant";
                };
            };
        };

        hardware.raspberry-pi.config.all.base-dt-params.spi = {
            enable = true;
            value = "on";
        };
    };
}
