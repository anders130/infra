{
    den.aspects.acme-dns-server.nixos = {config, ...}: let
        inherit (config.networking) domain;
        apiPort = 8080;
    in {
        services.acme-dns = {
            enable = true;
            settings = {
                general = {
                    domain = "acme.${domain}";
                    nsname = "ns-acme.${domain}";
                    nsadmin = "admin.${domain}";
                    listen = "0.0.0.0:53";
                    protocol = "both";
                };
                database = {
                    engine = "sqlite";
                    connection = "/var/lib/acme-dns/acme-dns.db";
                };
                api = {
                    ip = config.my.networking.tailscaleIP;
                    port = apiPort;
                    tls = "none";
                    disable_registration = false;
                };
                logconfig.loglevel = "info";
            };
        };

        networking.firewall = {
            allowedTCPPorts = [53];
            allowedUDPPorts = [53];
            interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [apiPort];
        };
    };
}
