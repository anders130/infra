{
    config,
    lib,
    withSystem,
    ...
}: let
    inherit (builtins) head;
    inherit (lib) concatLines mkOption naturalSort types;
in {
    options.text = mkOption {
        default = {};
        type = types.lazyAttrsOf (types.separatedString "");
    };
    config.text.generatedFiles =
        withSystem (head config.systems) (psArgs: lib.attrNames psArgs.config.files.file)
        |> naturalSort
        |> map (path: "- `${path}`")
        |> concatLines
        |> (s: s + "\n");
}
