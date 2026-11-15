{config, ...}: {
    networks = {
        home = {
            role = "lan";
            subnet = "192.168.178.0/24";
            gateway = config.hosts.fritzbox;
            nameservers = [config.hosts.dns-pi "1.1.1.1"];
        };
        direct = {subnet = "192.168.2.0/24";};
        vpn = {role = "tailnet";};
        internet = {role = "public";};
        domains."gollub.dev" = {
            hosts = [config.hosts.ds1 config.hosts.vps1];
            primary = config.hosts.ds1;
        };
    };
}
