{
    config,
    lib,
    ...
}: let
    inherit (config.hostsLib) ipOn mkProxiedServices mkNfsMounts;
    rackflix = config.hosts.rackflix;
    homeIp = ipOn rackflix config.networks.home;
    directIp = ipOn rackflix config.networks.direct;
    proxied = mkProxiedServices {
        services = rackflix.services;
        ip = homeIp;
        vhostSuffix = "rackflix";
    };
in {
    den.aspects.ds1.nixos = {
        my.services.caddy = {
            inherit (proxied) virtualHosts;
        };
        my.dashboard.services =
            (lib.mapAttrs (_: svc: svc // {host = "rackflix";}) proxied.homepageServices)
            // {
                plex =
                    proxied.homepageServices.plex
                    // {
                        host = "rackflix";
                        actions = [
                            {
                                id = "scan";
                                label = "Scan";
                                widgetAction = "scan";
                            }
                        ];
                    };
            };
        fileSystems = mkNfsMounts {
            ip = directIp;
            volumes = rackflix.services.nfs.volumes;
            mountPrefix = "/mnt/rackflix";
            options = [
                "nfsvers=4.1" # latest version supported by QNAP
                "rsize=1048576" # max supported read size for NFSv4 (1 MiB)
                "wsize=1048576" # max write size
                "noatime"
                "hard"
                "timeo=600"
                "retrans=2"
                "noauto" # prevent mounting on boot
                "x-systemd.automount" # lazy mounting
                "x-systemd.idle-timeout=600" # auto-unmount after 600 seconds of inactivity
            ];
        };
    };
}
