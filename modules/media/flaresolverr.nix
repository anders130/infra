{den, ...}: {
    den.aspects.flaresolverr.includes = with den.aspects; [mullvad];

    den.aspects.flaresolverr.nixos = {
        services.flaresolverr = {
            enable = true;
            port = 8191;
            openFirewall = false;
        };

        systemd.services.flaresolverr.vpnConfinement = {
            enable = true;
            vpnNamespace = "mullvad";
        };

        vpnNamespaces.mullvad.portMappings = [
            {
                from = 8191;
                to = 8191;
            }
        ];
    };
}
