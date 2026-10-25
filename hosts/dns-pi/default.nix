{
    den,
    config,
    inputs,
    ...
}: {
    den.hosts.aarch64-linux.dns-pi = {
        instantiate = inputs.nixos-raspberrypi.lib.nixosSystem;
    };
    hosts.dns-pi = {
        nixos = true;
        sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIv2l7s6laQQJSikagaOFWhorQvWYIA9e5SxyB2sWpf9";
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.2";
            }
        ];
        aspects = with den.aspects; [
            raspberry

            caddy
            mosquitto
            pihole
            sops
            zigbee
        ];
    };
    den.aspects.dns-pi.nixos = {
        imports = [inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base];
        system.stateVersion = "25.05";
        sdImage.expandOnBoot = true;
        sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
    };
    den.aspects.dns-pi.readme = {
        intro = "Raspberry Pi 4B handling DNS (Pihole), Zigbee proxy, and MQTT. Boots NixOS from an NVMe SSD connected via USB.";
        install = config.readmeLib.mkSdImageInstall "the NVMe drive" "dns-pi";
    };
}
