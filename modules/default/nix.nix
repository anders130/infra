{config, ...}: let
    inherit (config.flake-file) nixConfig;
in {
    den.default.nixos = {
        nix = {
            gc = {
                automatic = true;
                options = "--delete-older-than 7d";
            };
            settings = {
                substituters = nixConfig.extra-substituters;
                trusted-public-keys = nixConfig.extra-trusted-public-keys;
                experimental-features = [
                    "nix-command"
                    "flakes"
                    "pipe-operators"
                ];
            };
        };
        nixpkgs.config.allowUnfree = true;
    };
}
