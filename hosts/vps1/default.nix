{
    den,
    config,
    lib,
    ...
}: {
    den.hosts.x86_64-linux.vps1 = {};
    hosts.vps1 = {
        nixos = true;
        sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINne+Dna4q8KW+QIZEZm4bTwCmZyOGKjiggsn9pF0Umy";
        interfaces = with config.networks; [
            {
                network = vpn;
                ip = "100.71.185.0";
            }
            {
                network = internet;
                interface = "enp1s0";
            }
        ];
        relay = {
            from = config.hosts.ds1;
            services = with config.serviceRegistry; [
                astroneer
                terraria
                tmodloader
                hytale
                space-engineers
                vintagestory
            ];
        };
        aspects = with den.aspects; [
            matrix

            acme-dns
            acme-dns-server
            caddy
            sops
            tailscale
        ];
    };
    den.aspects.vps1 = {
        nixos = {config, ...}: {
            boot = {
                initrd.availableKernelModules = ["virtio_pci" "virtio_scsi" "sd_mod"];
                loader = {
                    efi.canTouchEfiVariables = true;
                    systemd-boot.enable = true;
                };
            };

            networking = {
                useDHCP = true;
                firewall.allowedTCPPorts = [80 443 8448];
            };

            # Use SSH host key for sops instead of manually-generated age key
            sops.age = {
                keyFile = lib.mkForce null;
                sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
            };

            services.postgresql.dataDir = "/persist/postgresql";
            services.matrix-synapse.settings.media_store_path = "/persist/matrix-media";

            systemd.tmpfiles.rules = [
                "d /persist/postgresql 0700 postgres postgres -"
                "d /persist/matrix-media 0750 matrix-synapse matrix-synapse -"
            ];

            nixpkgs.hostPlatform = "x86_64-linux";
            system.stateVersion = "26.05";
        };
        readme = {
            intro = "VPS hosting Matrix/Element Call, game relay, and Caddy reverse proxy.";
        };
    };
}
