{config, ...}: {
    hosts.rackflix = {
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.4";
            }
            {
                network = direct;
                ip = "192.168.2.2";
            }
        ];
        services = {
            paperless.port = 8000;
            admin = rec {
                port = 8080;
                homepageKey = "rackflix";
                homepage = homeIp: {
                    name = "Rackflix";
                    category = "Platform";
                    href = "http://admin.rackflix";
                    widget = {
                        type = "qnap";
                        baseUrl = "http://${homeIp}:${toString port}";
                        usernameEnvVar = "QNAP_USERNAME";
                        passwordEnvVar = "QNAP_PASSWORD";
                    };
                    widgetSecrets = {
                        QNAP_USERNAME.name = "qnap/username";
                        QNAP_PASSWORD.name = "qnap/password";
                    };
                    providesHostMetrics = true;
                };
            };
            plex = rec {
                port = 32400;
                homepage = homeIp: {
                    name = "Plex";
                    category = "Media";
                    href = "http://plex.rackflix";
                    widget = {
                        type = "plex";
                        baseUrl = "http://${homeIp}:${toString port}";
                        tokenEnvVar = "PLEX_TOKEN";
                    };
                    widgetSecrets.PLEX_TOKEN.name = "plex/token";
                };
            };
            nfs.volumes = ["Data" "appdata"];
        };
    };
    den.aspects.rackflix.readme = {
        title = "rackflix";
        intro = "QNAP NAS hosting media, documents, and backups.";
        sections = [
            {
                title = "Warning";
                content = ''
                    > [!CAUTION]
                    > This host is **not managed by NixOS**. Configuration must be done manually through the QNAP admin interface.
                '';
            }
            {
                title = "Services";
                content = config.readmeLib.mkServicesTable (name: "http://${name}.rackflix") config.hosts.rackflix.services;
            }
        ];
    };
}
