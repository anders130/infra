{
    den.aspects.postgres.nixos = {
        lib,
        config,
        ...
    }: let
        inherit (builtins) attrNames;
        inherit (lib) mapAttrsToList mkOption types;
        cfg = config.my.services.postgres;
    in {
        options.my.services.postgres.databases = mkOption {
            type = types.attrsOf (types.submodule {
                options.superuser = mkOption {
                    type = types.bool;
                    default = false;
                };
            });
            default = {};
        };
        config.services.postgresql = {
            enable = true;
            ensureDatabases = attrNames cfg.databases;
            ensureUsers =
                cfg.databases
                |> mapAttrsToList (name: value: {
                    inherit name;
                    ensureDBOwnership = true;
                    ensureClauses = {inherit (value) superuser;};
                });
        };
    };
}
