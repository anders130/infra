{config, ...}: {
    hosts.fritzbox = {
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.1";
            }
        ];
        aliases = ["fritz.box"];
    };
}
