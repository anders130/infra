{
    inputs,
    release,
    ...
}: {
    imports = [
        inputs.flake-file.flakeModules.default
        inputs.flake-follows.flakeModules.flake-follows
        inputs.den.flakeModule
        inputs.flake-parts.flakeModules.touchup
    ];

    _module.args.release = "26.05";

    # flake-parts can't statically null-check formatter.<system>; drop it
    touchup.attr.formatter.enable = false;

    flake-file = {
        nixConfig.abort-on-warn = true;
        nixConfig.extra-experimental-features = ["pipe-operators"];
        formatter = pkgs: pkgs.alejandra-with-config;
        inputs = {
            flake-file.url = "github:vic/flake-file";
            flake-follows.url = "github:anders130/flake-follows";
            nixpkgs.url = "nixpkgs/nixos-${release}";
            unstable.url = "nixpkgs/nixos-unstable";
            flake-parts.url = "github:hercules-ci/flake-parts";
            nix-lib.url = "github:anders130/nix-lib";
            import-tree.url = "github:denful/import-tree";
            den.url = "github:denful/den";
            treefmt-nix = {
                url = "github:anders130/treefmt-nix";
                inputs.nixpkgs.follows = "nixpkgs";
            };
            nixpkgs-lib.follows = "nixpkgs";
        };
    };
}
