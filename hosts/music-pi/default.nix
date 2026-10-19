{
    den,
    config,
    inputs,
    ...
}: let
    rpi = inputs.nixos-raspberrypi.nixosModules;
in {
    den.hosts.aarch64-linux.music-pi = {
        instantiate = inputs.nixos-raspberrypi.lib.nixosSystem;
    };

    hosts.music-pi = {
        nixos = true;
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.147";
            }
        ];
        aspects = with den.aspects; [raspberry];
    };

    den.aspects.music-pi.nixos = {
        imports = [
            rpi.raspberry-pi-4.base
            rpi.raspberry-pi-4.bluetooth
        ];

        system.stateVersion = "25.11";

        sdImage.expandOnBoot = true;

        my.networking.alwaysOnline = false;

        hardware.raspberry-pi.config.all.dt-overlays.hifiberry-dacplus = {
            enable = true;
            params = {};
        };

        boot.kernelParams = [
            "snd_bcm2835.enable_hdmi=0"
            "snd_bcm2835.enable_headphones=0"
        ];
    };
}
