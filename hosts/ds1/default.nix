{
    den,
    config,
    ...
}: {
    den.hosts.x86_64-linux.ds1 = {};
    hosts.ds1 = {
        nixos = true;
        nixCache = true;
        sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE0m/4rDiIkBD78OMeGierlWBHuN9fEpBTZjk8MK8Gst";
        interfaces = with config.networks; [
            {
                network = home;
                ip = "192.168.178.6";
                interface = "enp12s0";
            }
            {
                network = direct;
                ip = "192.168.2.1";
                interface = "enp7s0";
            }
            {
                network = vpn;
                ip = "100.100.1.70";
            }
        ];
        aspects = with den.aspects; [
            actual
            home-assistant
            homebox
            nextcloud
            obsidian-livesync
            paperless
            searx
            tandoor

            acme-dns
            caddy
            esphome
            harmonia
            hearth
            ntfy
            sops
            tailscale

            audiobookshelf
            navidrome
            chordweave
            mover
            immich
            jellyfin
            flaresolverr
            prowlarr
            qbittorrent
            radarr
            seerr
            sonarr
            lidarr
            ytm-migrate
            whisparr
            stash
            tautulli

            authelia
            cockpit
            forgejo
            vaultwarden

            windows
        ];
    };
    den.aspects.ds1.nixos = {
        my.services.forgejo.sshHostKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCgRElbuouH/3tqsDYc6avvYT/6zT3WCiHlNfTpMObhUHnBaVum4X1fLOGNidsC89kgmWMQ0qtQ6dm7/yiGL9J7dkhIntdBF/F0eNsrqDfm9slAnBPnIyejVwStLtMzynjjTKO/1k4YhgvXqoREdEniteJCa7LhZ7XTrALPk3i/2r8ig2k72AB06BJJ2oxVrYK/B76XeBgEoGPV6nhHxH6A81tbsUQZQgVz54XsfgnuMS0XQAbiICCfCOS4ibd4MDStA2kjOkpHEAsrOjmfNgGAacXuU6+x/GLsbUBETx/i15uLvBgqN8GgMdq+0hAm1VYlLZjrloU6Fij5pYyy6jNjel0Hd3pewBO4ME2lMl5OkYwt5dId9OfZNUH/nqbaxDm5UMcuUyl2N+5hLQSEtZ7sVzAut+0uoAooNkJOzQ+uhgEapDEdz2cfHzIJXNrHGn6YcRoFKHVMTcOezCHP3LG99zQea6Mv/D4kpXHoX8E7opPcvtuqi7GNNxC3qvu3ajRUHpTcWyTlljTNWV9aOlpZwnRjrcDxZ6QSuX1mha96UQRijx2X//Q+MzcvqiWN/5PAUZvy0RNCXz5UmXFn/0BKJGkBoGbNfuP6zDqrADMkXQ0+X6GtaanPFjvBSOiG6UhfTmhRxPBp39b0et1T3KBAEblnaXVFs+McckK5f/MytQ==";
    };
}
