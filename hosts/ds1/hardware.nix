{
    den.aspects.ds1.nixos = {
        boot = {
            initrd.availableKernelModules = ["usb_storage"];
            kernelModules = ["kvm-amd"];
            loader = {
                efi.canTouchEfiVariables = true;
                systemd-boot.enable = true;
            };
            binfmt.emulatedSystems = ["aarch64-linux"];
        };
        hardware = {
            cpu.amd.updateMicrocode = true;
            enableRedistributableFirmware = true;
        };
        networking.useDHCP = true;

        nix.settings = {
            extra-substituters = ["https://nixos-raspberrypi.cachix.org" "https://anders130.cachix.org"];
            extra-trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=" "anders130.cachix.org-1:mCAq0L6Ld3lG7gxJVHGzKr2rqUZ5qs5YoERxoSjMOXs="];
        };

        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "24.11";
    };
}
