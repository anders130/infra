{
    den,
    config,
    inputs,
    ...
}: {
    den.hosts.aarch64-linux.led-pi = {
        instantiate = inputs.nixos-raspberrypi.lib.nixosSystem;
    };

    hosts.led-pi = {
        nixos = true;
        sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH6wz6d0D1QgsxAoBz2TNNxStWw/Z0cdH9yhZe2wbp9c";
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.85";
            }
        ];
        aspects = with den.aspects; [raspberry];
    };

    den.aspects.led-pi.nixos = {
        imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base];
        system.stateVersion = "24.05";
    };
}
