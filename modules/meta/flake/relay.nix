{
    config,
    lib,
    ...
}: {
    options.serviceRelays = lib.mkOption {
        default = [];
        type = lib.types.listOf (lib.types.submodule {
            options = {
                from = lib.mkOption {type = lib.types.raw;};
                via = lib.mkOption {type = lib.types.raw;};
                services = lib.mkOption {type = lib.types.listOf lib.types.raw;};
            };
        });
    };

    config.flake.relay = map (entry: {
        inherit (entry) from via;
        ports = from_config: let
            resolvePorts = field: svc: let
                p = svc.ports.${field};
            in
                if lib.isFunction p
                then p from_config
                else p;
        in {
            tcp = lib.concatMap (resolvePorts "tcp") entry.services;
            udp = lib.concatMap (resolvePorts "udp") entry.services;
        };
    })
    config.serviceRelays;
}
