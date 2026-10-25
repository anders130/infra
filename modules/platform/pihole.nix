{inputs, ...}: {
    serviceRegistry.pihole = {
        web = {
            subdomain = "pihole";
            port = 168;
            local = true;
            aliases = ["pi.hole"];
        };
        dashboard = nixos: {
            name = "Pi-hole";
            category = "Platform";
            widget = {
                type = "pihole";
                baseUrl = nixos.my.services.pihole.url;
            };
        };
        actions = [
            {
                id = "pause";
                label = "Pause";
                widgetAction = "pause";
            }
            {
                id = "resume";
                label = "Resume";
                widgetAction = "resume";
            }
        ];
    };

    den.aspects.pihole.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (builtins) concatMap filter;
        inherit (lib) attrByPath mapAttrsToList;
        inherit (config.my.services.pihole) port;

        allConfigs =
            inputs.self.nixosConfigurations
            |> mapAttrsToList (_: value: value.config)
            |> filter (config: config.my.networking.address != null);

        hostnameEntry = config: "${config.my.networking.address} ${config.networking.hostName}";

        caddyEntries = config: let
            inherit (config.my.networking) address;
        in
            (attrByPath ["my" "services" "caddy" "virtualHosts"] {} config)
            |> mapAttrsToList (name: value: {inherit name value;})
            |> filter ({value, ...}: value.local)
            |> map ({name, ...}: "${address} ${lib.removePrefix "http://" name}");

        hosts = concatMap (config: [(hostnameEntry config)] ++ caddyEntries config) allConfigs;
    in {
        services = {
            pihole-ftl = {
                enable = true;
                openFirewallDNS = true;
                settings = {
                    dns = {
                        inherit hosts;
                        upstreams = ["8.8.8.8" "8.8.4.4"];
                        listeningMode = "LOCAL";
                        rateLimit = {
                            count = 0;
                            interval = 0;
                        };
                    };
                    dhcp.active = false;
                    webserver.api.pwhash = "";
                };
            };
            pihole-web = {
                enable = true;
                ports = [port];
            };
        };
    };
}
