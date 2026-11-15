{den, ...}: let
    port = 8686;
in {
    serviceRegistry.lidarr = {
        web = {
            subdomain = "lidarr";
            local = true;
            inherit port;
        };
        dashboard = nixos: {
            name = "Lidarr";
            category = "Media";
            visibility = "admin";
            widget = {
                type = "lidarr";
                baseUrl = nixos.my.services.lidarr.internalUrl;
                apiKeyEnvVar = "LIDARR_API_KEY";
            };
            widgetSecrets.LIDARR_API_KEY = {
                name = "lidarr/api_key";
                sopsFile = nixos.my.secretFiles.lidarr;
            };
            resourceUnits = ["lidarr.service"];
        };
    };

    den.aspects.lidarr.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        cfg = config.services.lidarr;
        own = config.my.services.lidarr;
        recycleBin = "${cfg.dataDir}/recycle";
        youtubeCookies = "${cfg.dataDir}/youtube-cookies.txt";
        downloadDir = "${cfg.dataDir}/youtube-downloads";
        python = pkgs.python3.withPackages (ps: [ps.requests]);
        desired = pkgs.writeText "lidarr-desired.json" (builtins.toJSON {
            rootFolder = {
                name = "Music";
                path = own.rootFolder;
            };
            inherit (own) metadataProfile naming;
            mediaManagement = {
                inherit recycleBin;
                recycleBinCleanupDays = 30;
            };
            qualityProfile = {
                name = own.qualityProfile;
                allowed = [
                    "Unknown"
                    "Trash Quality Lossy"
                    "Poor Quality Lossy"
                    "Low Quality Lossy"
                    "Mid Quality Lossy"
                    "High Quality Lossy"
                ];
            };
            cookiesPath = youtubeCookies;
            metadataProvider = {};
            indexers = [
                {
                    name = "YouTube";
                    implementation = "YouTubeIndexer";
                    fields.cookiePath = youtubeCookies;
                }
            ];
            downloadClients = [
                {
                    name = "YouTube";
                    implementation = "YoutubeClient";
                    options.enable = true;
                    fields = {
                        downloadPath = downloadDir;
                        cookiePath = youtubeCookies;
                    };
                }
            ];
        });
        tubifarry = pkgs.fetchzip {
            url = "https://github.com/TypNull/Tubifarry/releases/download/v2.3.0.2/Tubifarry-v2.3.0.2.net8.0.zip";
            stripRoot = false;
            sha256 = "0c566sq8kd8vf4sa7wjyxs27gwvkq9ay2y6g3rml01nbkn63w3k2";
        };
    in {
        options.my.services.lidarr = {
            apiKeyFile = mkOption {
                type = types.path;
                default = config.sops.secrets."lidarr/api_key".path;
                description = "Runtime path of the file holding Lidarr's API key.";
            };
            rootFolder = mkOption {
                type = types.str;
                description = "Lidarr root folder that new artists are added under.";
            };
            naming = mkOption {
                type = types.attrs;
                description = "Lidarr config/naming fields applied verbatim; renameTracks is always forced on so new imports follow them, existing files are only renamed by an explicit Rename command.";
            };
            qualityProfile = mkOption {
                type = types.str;
                readOnly = true;
                default = "YouTube";
                description = "Quality profile new artists are added with.";
            };
            metadataProfile = mkOption {
                type = types.str;
                readOnly = true;
                default = "Everything";
                description = "Metadata profile new artists are added with; allows every release type and status.";
            };
        };

        config = {
            sops.secrets."lidarr/api_key".sopsFile = config.my.secretFiles.lidarr;

            sops.templates."lidarr.env".content = ''
                LIDARR__AUTH__APIKEY=${config.sops.placeholder."lidarr/api_key"}
            '';

            services.lidarr = {
                enable = true;
                openFirewall = false;
                package = pkgs.callPackage ./_package.nix {};
                settings.server.port = port;
                environmentFiles = [config.sops.templates."lidarr.env".path];
            };

            systemd.services.lidarr.path = [pkgs.nodejs pkgs.ffmpeg];

            systemd.tmpfiles.rules = [
                "d ${cfg.dataDir}/plugins 0755 ${cfg.user} ${cfg.group} -"
                "d ${cfg.dataDir}/plugins/TypNull 0755 ${cfg.user} ${cfg.group} -"
                "d ${downloadDir} 0750 ${cfg.user} ${cfg.group} -"
                "d ${recycleBin} 0750 ${cfg.user} ${cfg.group} -"
                "L+ ${cfg.dataDir}/plugins/TypNull/Tubifarry - - - - ${tubifarry}"
            ];

            systemd.paths.lidarr-provision = {
                wantedBy = ["lidarr.service"];
                pathConfig.PathChanged = youtubeCookies;
            };

            systemd.services.lidarr-provision = {
                restartTriggers = [desired];
                after = ["lidarr.service"];
                requires = ["lidarr.service"];
                wantedBy = ["lidarr.service" "multi-user.target"];
                environment = {
                    LIDARR_URL = own.internalUrl;
                    LIDARR_API_KEY_FILE = own.apiKeyFile;
                };
                serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${python}/bin/python3 ${./provision.py} ${desired}";
                };
            };

            users.users.lidarr.extraGroups = ["users"];
        };
    };
}
