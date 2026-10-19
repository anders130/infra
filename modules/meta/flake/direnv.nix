{
    gitignore = [
        ".direnv"
        ".env"
    ];
    perSystem = {lib, ...}: {
        files.file.".envrc".text = lib.concatLines [
            "dotenv_if_exists"
            "use flake"
        ];
    };
}
