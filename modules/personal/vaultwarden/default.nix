{
    serviceRegistry.vaultwarden = {
        web = {
            subdomain = "vault";
            port = 8222;
        };
        sops.dotenv = true;
        dashboard = {
            name = "Vaultwarden";
            description = "Password manager";
            category = "Personal";
        };
    };

    den.aspects.vaultwarden.nixos = {
        config,
        lib,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.vaultwarden;
        ROCKET_ADDRESS = "127.0.0.1";
        ROCKET_PORT = 8222;
    in {
        options.my.services.vaultwarden.backupDir = mkOption {
            type = types.str;
            default = "/var/backup/vaultwarden";
        };

        config = {
            services.vaultwarden = {
                inherit (svc) backupDir;
                enable = true;
                environmentFile = config.sops.secrets.vaultwarden.path;
                config = {
                    inherit ROCKET_ADDRESS ROCKET_PORT;
                    WEBSOCKET_ENABLED = true;
                    SIGNUPS_ALLOWED = false;
                    DOMAIN = svc.url;
                    SMTP_HOST = "smtp.strato.de";
                    SMTP_PORT = 587;
                    SMTP_FROM = "vaultwarden@${config.networking.domain}";
                    SMTP_SECURITY = "starttls";
                    EXPERIMENTAL_CLIENT_FEATURE_FLAGS = builtins.concatStringsSep "," [
                        "ssh-key-vault-item"
                        "ssh-agent"
                    ];
                };
            };

            users.users.admin.extraGroups = ["vaultwarden"];

            my.services.caddy.virtualHosts.${svc.fqdn} = {
                extraConfig = ''
                    encode zstd gzip
                '';
                headers = ''
                    header_up X-Real-IP {remote_host}
                '';
            };
        };
    };

    den.aspects.vaultwarden.readme = {
        title = "Vaultwarden";
        intro = "Self-hosted [Bitwarden](https://bitwarden.com)-compatible password manager.";
        sections = [
            {
                title = "Dependencies";
                content = ''
                    - [caddy](/modules/platform/caddy.nix)
                    - [sops](/modules/platform/sops)
                '';
            }
            {
                title = "Usage";
                content = ''
                    ```nix
                    den.aspects.<host>.includes = with den.aspects; [vaultwarden];
                    networking.domain = "example.com"; # serves at vault.example.com
                    my.services.vaultwarden.backupDir = "/path/to/backup"; # optional
                    ```
                '';
            }
            {
                title = "Secrets";
                content = ''
                    Edit the secrets file:

                    ```bash
                    sops hosts/ds1/secrets/vaultwarden.env
                    ```

                    Update keys after adding a new device:

                    ```bash
                    sops updatekeys hosts/ds1/secrets/vaultwarden.env
                    ```

                    ### ADMIN_TOKEN

                    ```bash
                    nix shell nixpkgs#libargon2 nixpkgs#openssl --command \
                        sh -c 'echo -n "YourPassword" | argon2 "$(openssl rand -base64 32)" -e -id -k 19456 -t 2 -p 1'
                    ```
                '';
            }
        ];
    };
}
