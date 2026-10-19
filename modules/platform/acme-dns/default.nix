{den, ...}: {
    den.aspects.acme-dns = {
        includes = [den.aspects.caddy];
        nixos = {
            config,
            pkgs,
            ...
        }: let
            inherit (config.networking) domain;
        in {
            sops.secrets."caddy-acmedns" = {
                sopsFile = config.my.secretFiles.acme-dns;
                format = "json";
                key = "";
                owner = "caddy";
                group = "caddy";
            };
            services.caddy = {
                package = pkgs.caddy.withPlugins {
                    plugins = ["github.com/caddy-dns/acmedns@v0.7.0"];
                    hash = "sha256-hlu5ryAU9eUGVQmDrAF6tWKQ6wbJTwkVg8crx4497kU=";
                };
                globalConfig = ''
                    acme_dns acmedns ${config.sops.secrets."caddy-acmedns".path}
                '';
                virtualHosts."*.${domain}".extraConfig = ''
                    tls {
                        dns acmedns ${config.sops.secrets."caddy-acmedns".path}
                        propagation_timeout -1
                    }
                '';
            };
        };
    };
}
