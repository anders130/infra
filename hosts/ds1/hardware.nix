{config, ...}: {
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
            inherit (config.flake-file.nixConfig) extra-substituters extra-trusted-public-keys;
        };

        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "24.11";
    };
}
