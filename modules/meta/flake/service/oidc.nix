{
    config,
    lib,
    ...
}: {
    config.den.aspects = lib.mapAttrs (name: svc: {
        nixos = {
            config,
            lib,
            ...
        }: let
            oidc = svc.oidc;
            clientId =
                if oidc.clientId != null
                then oidc.clientId
                else name;
            secretName =
                if oidc.secretName != null
                then oidc.secretName
                else "${name}/oidc_client_secret";
        in {
            imports = lib.optionals (oidc != null && oidc.nixos != null && oidc.autoEnable) [oidc.nixos];

            options = lib.optionalAttrs (oidc != null) {
                my.services.${name}.oidc = {
                    issuerUrl = lib.mkOption {type = lib.types.str;};
                    clientId = lib.mkOption {
                        type = lib.types.str;
                        default = clientId;
                    };
                };
            };

            config = lib.mkMerge [
                (lib.optionalAttrs (oidc != null) {
                    sops.secrets.${secretName} = {
                        sopsFile = oidc.sopsFile;
                        mode = "0400";
                    };
                })
                (lib.optionalAttrs (oidc != null && oidc.autoEnable) {
                    my.services.${name}.oidc.issuerUrl = "https://auth.${config.networking.domain}";
                })
                (lib.optionalAttrs (svc.access != null) {
                    assertions = [
                        {
                            assertion = (svc.web != null && svc.web.protect) || oidc != null;
                            message = "serviceRegistry.${name}.access requires web.protect = true or an oidc block -- access control needs an actual enforcement point.";
                        }
                    ];
                })
            ];
        };
    })
    config.serviceRegistry;
}
