{inputs, ...}: {
    den.aspects.ds1.nixos = {config, ...}: {
        my.services.caddy.virtualHosts."led.${config.networking.domain}" = {
            from = inputs.self.nixosConfigurations.led-pi.config.my.networking.address;
            port = 5000;
        };
    };
}
