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
        in {
            hostname = address;
            profiles.system.path =
                inputs.deploy-rs.lib.${cfg.config.nixpkgs.hostPlatform.system}.activate.nixos cfg;
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
