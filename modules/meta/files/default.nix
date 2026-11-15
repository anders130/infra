{
    inputs,
    lib,
    ...
}: {
    flake-file.inputs.files = {
        url = "github:mightyiam/files";
        flake = false;
    };
    imports = [(inputs.files + "/flake-module.nix")];

    perSystem = {
        config,
        pkgs,
        ...
    }: {
        _module.args.writeLines = name: lines:
            pkgs.writeText name (lib.concatLines lines);

        packages.write-files = config.files.writer.drv;

        pre-commit.settings.hooks.write-files = {
            enable = true;
            name = "write-files";
            description = "Generate repository files";
            entry = lib.getExe (pkgs.writeShellApplication {
                name = "write-files-hook";
                text = ''
                    command -v nix > /dev/null 2>&1 || exit 0
                    exec nix run --accept-flake-config .#write-files -- "$@"
                '';
            });
            always_run = true;
            pass_filenames = false;
        };
    };
}
