{
    inputs,
    config,
    ...
}: let
    inherit (config) nixCacheHost;
in {
    serviceRegistry.harmonia.web = {
        subdomain = "cache";
        local = true;
        trustedCert = true;
        port = 8084;
    };

    den.default.nixos = {config, ...}: let
        cache = inputs.self.nixosConfigurations.${nixCacheHost._name}.config.my;
    in {
        nix.settings = {
            extra-substituters = [
                (
                    if config.my.networking.address != null
                    then cache.services.harmonia.url
                    else "http://${cache.networking.tailscaleIP}:${toString cache.services.harmonia.port}"
                )
            ];
            extra-trusted-public-keys = ["cache.gollub.dev-1:TtC91GN59qEW54Qv7Bw/bDcdu68dGc18K+XKTAtJ2Jc="];
        };
    };

    den.aspects.harmonia.nixos = {config, ...}: let
        inherit (config.my.services.harmonia) port;
    in {
        sops.secrets."harmonia/cache-priv-key".sopsFile = config.my.secretFiles.harmonia;
        services.harmonia.cache = {
            enable = true;
            signKeyPaths = [config.sops.secrets."harmonia/cache-priv-key".path];
            settings.bind = "[::]:${toString port}";
        };
        networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts = [port];
    };

    den.aspects.harmonia.readme = {
        title = "Nix Cache (harmonia)";
        intro = "Self-hosted Nix binary cache ([nix-community/harmonia](https://github.com/nix-community/harmonia)) serving the cache host's `/nix/store` to the fleet, so hosts substitute pre-built closures instead of round-tripping through cachix.";
        sections = [
            {
                title = "Access";
                content = ''
                    Served at `https://cache.gollub.dev` through Caddy with the
                    wildcard cert. The name only resolves via pihole, to the cache
                    host's LAN address -- there is no public DNS record or
                    port-forward for it. harmonia is unauthenticated and serves the
                    entire store, so LAN + tailnet is the trust boundary.

                    Every host with a LAN address uses that URL. A host without
                    one (`vps1`) has no LAN route and no pihole, so it uses plain
                    http on port 8084 at the cache host's Tailscale address,
                    which the firewall opens on `tailscale0` only.

                    http there is fine: NARs are signed with the key above
                    regardless, and Tailscale (WireGuard) encrypts the traffic.
                    Nothing is provisioned at runtime -- no caches to create, no
                    tokens. Retention is ordinary host GC (`nix.gc` /
                    `nix.optimise`) on the cache host.
                '';
            }
        ];
    };
}
