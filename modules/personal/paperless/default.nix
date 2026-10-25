{
    serviceRegistry.paperless = {
        web = {
            subdomain = "paperless";
            port = 28981;
        };
        dashboard = nixos: {
            name = "Paperless";
            description = "Document manager";
            category = "Personal";
            widget = {
                type = "paperless";
                baseUrl = nixos.my.services.paperless.url;
                username = "admin";
                passwordEnvVar = "PAPERLESS_PASSWORD";
            };
            widgetSecrets.PAPERLESS_PASSWORD.name = "paperless/admin_password";
            resourceUnits = ["paperless-web.service"];
        };
        access = {};
    };

    den.aspects.paperless.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        svc = config.my.services.paperless;
    in {
        options.my.services.paperless = {
            dataDir = mkOption {
                type = types.str;
                default = "/var/lib/paperless/data";
                description = "Directory Paperless stores its data files under.";
            };
            mediaDir = mkOption {
                type = types.str;
                default = "/var/lib/paperless/media";
                description = "Directory Paperless stores archived documents under.";
            };
            consumptionDir = mkOption {
                type = types.str;
                default = "/var/lib/paperless/consume";
                description = "Directory Paperless watches for new documents to import.";
            };
        };

        config.services.paperless = {
            enable = true;
            dataDir = svc.dataDir;
            mediaDir = svc.mediaDir;
            consumptionDir = svc.consumptionDir;
            consumptionDirIsPublic = true;
            passwordFile = config.sops.secrets."PAPERLESS_PASSWORD".path;
            domain = svc.fqdn;
            configureTika = true;
            settings = {
                PAPERLESS_OCR_LANGUAGE = "deu+eng";
                # NFS mount: inotify misses writes from other clients, poll instead.
                PAPERLESS_CONSUMER_POLLING = 30;
            };
        };

        # independent trigger to fix restarting scheduling issues
        config.systemd.services.paperless-web.wantedBy = ["multi-user.target"];
        config.systemd.services.paperless-consumer.wantedBy = ["multi-user.target"];
        config.systemd.services.paperless-task-queue.wantedBy = ["multi-user.target"];

        # Scanner SMB-writes here via QNAP; destination fixed (Windows-only
        # config tool). Files land owned by admin, not paperless - chmod
        # after the fact so paperless can read/delete them.
        config.systemd.paths.paperless-fix-consume-perms = {
            description = "Watch Paperless consume dir for scanner-dropped files";
            wantedBy = ["multi-user.target"];
            pathConfig.PathChanged = config.services.paperless.consumptionDir;
        };
        config.systemd.services.paperless-fix-consume-perms = {
            description = "Fix permissions on scanner-dropped files in Paperless consume dir";
            serviceConfig = {
                Type = "oneshot";
                ExecStart = "${pkgs.coreutils}/bin/chmod -R a+rwX ${config.services.paperless.consumptionDir}";
            };
        };
    };
}
