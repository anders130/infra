{inputs, ...}: {
    flake-file = {
        nixConfig = {
            extra-substituters = ["https://nixos-raspberrypi.cachix.org"];
            extra-trusted-public-keys = ["nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="];
        };
        inputs.nixos-raspberrypi = {
            url = "github:nvmd/nixos-raspberrypi/main";
            inputs.flake-compat.follows = "";
        };
    };
    flake-follows.exclude = ["nixos-raspberrypi/nixpkgs"];
    den.aspects.raspberry.nixos = {lib, ...}: {
        imports = [inputs.nixos-raspberrypi.nixosModules.sd-image];
        nixpkgs.overlays = [
            (_: prev: {ubootRaspberryPi_64bit = prev.ubootRaspberryPi4_64bit;})
        ];
        networking = {
            networkmanager.enable = lib.mkForce false;
            useDHCP = false;
            interfaces = {
                wlan0.useDHCP = true;
                eth0.useDHCP = true;
            };
        };
        boot.supportedFilesystems.zfs = false;
    };
}
