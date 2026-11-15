{
    inputs,
    lib,
    ...
}: {
    flake-file.inputs.deploy-rs = {
        url = "github:serokell/deploy-rs";
        inputs.nixpkgs.follows = "nixpkgs";
    };
    flake.deploy = let
        mkNode = host: let
            cfg = inputs.self.nixosConfigurations.${host};
            net = cfg.config.my.networking;
            address =
                if net.address != null
                then net.address
                else net.tailscaleIP;
            deployPkgs = cfg.pkgs.appendOverlays [
                inputs.deploy-rs.overlays.default
                (_: prev: {
                    deploy-rs = {
                        inherit (cfg.pkgs) deploy-rs;
                        inherit (prev.deploy-rs) lib;
                    };
                })
            ];
        in {
            hostname = address;
            profiles.system.path = deployPkgs.deploy-rs.lib.activate.nixos cfg;
        };
    in {
        sshUser = "admin";
        user = "root";
        magicRollback = true;
        autoRollback = true;
        nodes = lib.mapAttrs (host: _: mkNode host) inputs.self.nixosConfigurations;
    };
    perSystem = {system, ...}:
        lib.optionalAttrs (inputs.deploy-rs.lib ? ${system}) {
            checks = inputs.deploy-rs.lib.${system}.deployChecks inputs.self.deploy;
            apps.deploy = inputs.deploy-rs.apps.${system}.default;
        };
}
