{den, ...}: {
    serviceRegistry.nextcloud = {
        web.subdomain = "cloud";
        dashboard = nixos: {
            name = "Nextcloud";
            description = "File sync & cloud";
            category = "Personal";
            widget = {
                type = "nextcloud";
                baseUrl = nixos.my.services.nextcloud.url;
                username = "admin";
                passwordEnvVar = "NEXTCLOUD_PASSWORD";
            };
            widgetSecrets.NEXTCLOUD_PASSWORD = {
                name = "nextcloud/adminPass";
                sopsFile = nixos.my.secretFiles.nextcloud;
            };
            resourceUnits = ["phpfpm-nextcloud.service"];
        };
        access = {};
    };

    den.aspects.nextcloud.includes = with den.aspects; [postgres];

    den.aspects.nextcloud.nixos = {
        config,
        pkgs,
        ...
    }: let
        cfg = config.services.nextcloud;
    in {
        sops.secrets = let
            c = {
                mode = "0440";
                sopsFile = config.my.secretFiles.nextcloud;
                owner = "nextcloud";
            };
        in {
            "nextcloud/adminPass" = c;
            "nextcloud/dbPass" = c;
        };
        services.nextcloud = {
            enable = true;
            package = pkgs.nextcloud33;
            config = {
                adminuser = "admin";
                adminpassFile = config.sops.secrets."nextcloud/adminPass".path;
            };
            settings = {
                default_phone_region = "DE";
                maintenance_window_start = 1;
                log_type = "file";
                "localstorage.umask" = 002;
            };
            phpOptions = {
                "opcache.interned_strings_buffer" = "16";
                output_buffering = "off";
            };
            extraApps = {
                inherit
                    (pkgs.nextcloud33Packages.apps)
                    bookmarks
                    calendar
                    contacts
                    mail
                    ;
                theming_customcss = pkgs.fetchNextcloudApp {
                    sha256 = "sha256-Fgu31s+K4MFUgvNe9mAVHi9C0iJnv40v1onUMk+lFZk=";
                    url = "https://github.com/nextcloud-releases/theming_customcss/releases/download/v1.20.0/theming_customcss.tar.gz";
                    license = "agpl3Only";
                };
            };
        };
        systemd.tmpfiles.settings."50-nextcloud".${cfg.datadir}.d = {
            user = "nextcloud";
            group = "nextcloud";
            mode = "0750";
        };
    };
}
