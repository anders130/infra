{den, ...}: {
    gitignore = [".pytest_cache" "__pycache__"];

    serviceRegistry."ytm-review" = {
        web = {
            subdomain = "music-review";
            port = 8095;
            protect = true;
            local = true;
            trustedCert = true;
        };
        access = {};
        dashboard = {
            name = "Music review";
            description = "YouTube Music migration";
            icon = "youtube-music";
            category = "Media";
            visibility = "admin";
            widget.type = "link";
            resourceUnits = ["ytm-migrate-review.service"];
        };
    };

    den.aspects.ytm-migrate = {
        includes = with den.aspects; [ytm-review lidarr navidrome];

        nixos = {
            config,
            lib,
            pkgs,
            ...
        }: let
            inherit (lib) mkOption types;
            cfg = config.my.services.ytmMigrate;
            user = "ytm-migrate";
            stateDir = "/var/lib/${user}";
            navidrome = config.services.navidrome.settings;
            lidarr = config.my.services.lidarr;
            environment = {
                YTM_STATE = "${stateDir}/state.db";
                YTM_PLAYLISTS = builtins.toJSON cfg.playlists;
                LIDARR_URL = lidarr.internalUrl;
                LIDARR_API_KEY_FILE = config.sops.secrets."${user}/lidarr_api_key".path;
                LIDARR_ROOT_FOLDER = lidarr.rootFolder;
                LIDARR_QUALITY_PROFILE = lidarr.qualityProfile;
                LIDARR_METADATA_PROFILE = lidarr.metadataProfile;
                NAVIDROME_URL = "http://${navidrome.Address}:${toString navidrome.Port}";
                NAVIDROME_USER = cfg.navidromeUser;
                LISTENBRAINZ_TOKEN_FILE = config.sops.secrets."${user}/listenbrainz_token".path;
            };
            sudo = "${config.security.wrapperDir}/sudo";
            wrapper = pkgs.writeShellScriptBin "ytm-migrate" ''
                exec ${sudo} -u ${user} ${pkgs.coreutils}/bin/env ${
                    environment
                    |> lib.mapAttrsToList (name: value: lib.escapeShellArg "${name}=${value}")
                    |> lib.concatStringsSep " "
                } ${cfg.package}/bin/ytm-migrate "$@"
            '';
        in {
            options.my.services.ytmMigrate = {
                navidromeUser = mkOption {
                    type = types.str;
                    description = "Navidrome user whose library, stars, playlists and scrobbles receive the migrated data.";
                };
                playlists = mkOption {
                    type = types.listOf types.str;
                    description = "Titles of the YouTube Music playlists to migrate.";
                };
                package = mkOption {
                    type = types.package;
                    readOnly = true;
                    default = pkgs.callPackage ./_package.nix {};
                };
            };

            config = {
                users = {
                    users.${user} = {
                        isSystemUser = true;
                        group = user;
                    };
                    groups.${user} = {};
                };

                sops.secrets = {
                    "${user}/lidarr_api_key" = {
                        sopsFile = config.my.secretFiles.lidarr;
                        key = "lidarr/api_key";
                        owner = user;
                        mode = "0400";
                    };
                    "${user}/listenbrainz_token" = {
                        sopsFile = config.my.secretFiles.ytm-migrate;
                        owner = user;
                        mode = "0400";
                    };
                };

                systemd.tmpfiles.rules = ["d ${stateDir} 0750 ${user} ${user} -"];

                environment.systemPackages = [wrapper];

                systemd.services.ytm-migrate-review = {
                    wantedBy = ["multi-user.target"];
                    after = ["network-online.target"];
                    wants = ["network-online.target"];
                    inherit environment;
                    serviceConfig = {
                        User = user;
                        ExecStart = "${cfg.package}/bin/ytm-migrate review --port ${toString config.my.services."ytm-review".port}";
                        Restart = "on-failure";
                    };
                };
            };
        };
    };
}
