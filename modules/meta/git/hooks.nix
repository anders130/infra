{
    config,
    inputs,
    lib,
    ...
}: let
    inherit (config.flake-file.apps) write-flake;
    inherit (lib) getExe;
in {
    flake-file.inputs.git-hooks = {
        url = "github:cachix/pre-commit-hooks.nix";
        inputs.flake-compat.follows = "";
    };

    imports = [inputs.git-hooks.flakeModule];

    gitignore = [".pre-commit-config.yaml"];

    perSystem = {
        config,
        pkgs,
        ...
    }: {
        pre-commit.settings = {
            hooks = {
                alejandra = {
                    enable = true;
                    package = pkgs.alejandra-with-config;
                };
                write-flake = {
                    enable = true;
                    name = "write-flake";
                    description = "Generate flake.nix file using flake-file";
                    entry = getExe (pkgs.writeShellApplication {
                        name = "write-flake-hook";
                        text = ''
                            command -v nix > /dev/null 2>&1 || exit 0
                            exec ${getExe (write-flake pkgs)} "$@"
                        '';
                    });
                    always_run = true;
                    pass_filenames = false;
                };
            };
            package = pkgs.prek;
        };
        devShells.default = config.pre-commit.devShell;
    };
}
