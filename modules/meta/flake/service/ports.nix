{
    config,
    lib,
    ...
}: let
    inherit (config) serviceLib;
in {
    config.den.aspects = lib.mapAttrs (_: svc: {
        nixos = {config, ...}: {
            networking.firewall.allowedTCPPorts = serviceLib.resolveFn config svc.ports.tcp;
            networking.firewall.allowedUDPPorts = serviceLib.resolveFn config svc.ports.udp;
        };
    })
    config.serviceRegistry;
}
