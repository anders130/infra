{
    config,
    lib,
    ...
}: {
    config.den.aspects = lib.mapAttrs (name: svc: {
        nixos = lib.optionalAttrs (svc.sops != null && svc.sops.dotenv) {
            sops.secrets.${name} = {
                sopsFile = config.secretFiles.${name};
                format = "dotenv";
                owner = name;
                group = name;
            };
        };
    })
    config.serviceRegistry;
}
