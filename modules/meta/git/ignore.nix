{
    config,
    lib,
    ...
}: {
    options.gitignore = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        apply = lib.naturalSort;
    };
    config = {
        gitignore = ["result" ".worktrees"];
        perSystem = {lib, ...}: {
            files.file.".gitignore".text = lib.concatLines config.gitignore;
        };
    };
}
