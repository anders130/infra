# Nix Cache (harmonia)

Self-hosted Nix binary cache ([nix-community/harmonia](https://github.com/nix-community/harmonia)) serving the cache host's `/nix/store` to the fleet, so hosts substitute pre-built closures instead of round-tripping through cachix.

## Access

Served at `https://cache.gollub.dev` through Caddy with the
wildcard cert. The name only resolves via pihole, to the cache
host's LAN address -- there is no public DNS record or
port-forward for it. harmonia is unauthenticated and serves the
entire store, so LAN + tailnet is the trust boundary.

Every host defaults to that URL. A host with no LAN route and
no pihole (`vps1`) overrides to plain http on port 8084 at the
cache host's Tailscale address, which the firewall opens on
`tailscale0` only.

http there is fine: NARs are signed with the key above
regardless, and Tailscale (WireGuard) encrypts the traffic.
Nothing is provisioned at runtime -- no caches to create, no
tokens. Retention is ordinary host GC (`nix.gc` /
`nix.optimise`) on the cache host.
