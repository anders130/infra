{
    config,
    lib,
    ...
}: let
    hostsDir = ../../../hosts;
    stem = file: lib.head (lib.splitString "." file);

    filesIn = host: let
        dir = hostsDir + "/${host}/secrets";
    in
        if builtins.pathExists dir
        then builtins.readDir dir |> lib.mapAttrs' (file: _: lib.nameValuePair (stem file) (dir + "/${file}"))
        else {};

    merge = acc: files: let
        dup = lib.intersectAttrs acc files;
    in
        if dup != {}
        then throw "secretFiles: duplicate stem(s) [${lib.concatStringsSep ", " (lib.attrNames dup)}] across hosts/*/secrets/ -- prefix the filename with its host"
        else acc // files;
in {
    options.secretFiles = lib.mkOption {
        type = lib.types.attrsOf lib.types.path;
        default = {};
    };

    config.secretFiles =
        builtins.readDir hostsDir
        |> lib.filterAttrs (_: type: type == "directory")
        |> lib.mapAttrsToList (host: _: filesIn host)
        |> lib.foldl' merge {};

    config.den.default.nixos.my.secretFiles = config.secretFiles;
}
