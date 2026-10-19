{config, ...}: {
    networks = {
        home = {
            subnet = "192.168.178.0/24";
            gateway = "192.168.178.1";
            nameservers = [config.hosts.dns-pi "1.1.1.1"];
        };
        direct = {subnet = "192.168.2.0/24";};
        vpn = {type = "tailscale";};
    };

    domains."gollub.dev" = {
        hosts = [config.hosts.ds1 config.hosts.vps1];
        primary = config.hosts.ds1;
    };
}
