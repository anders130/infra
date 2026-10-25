{
    den.aspects.ds1.nixos = {config, ...}: {
        my.services = {
            vaultwarden.backupDir = "/mnt/rackflix/appdata/vaultwarden";
            jellyfin.systemUser = "admin";
            stash.dataDir = "/mnt/rackflix/appdata/.stash";
            immich = {
                mediaLocation = "/mnt/rackflix/appdata/immich";
                mediaGroup = "nextcloud";
            };
            paperless = {
                dataDir = "/mnt/rackflix/appdata/paperless/data";
                mediaDir = "/mnt/rackflix/appdata/paperless/media";
                consumptionDir = "/mnt/rackflix/appdata/paperless/consume";
            };
            windows = {
                dataSharePath = "/mnt/rackflix/data/downloads";
                appdataSharePath = "/mnt/rackflix/appdata/downloads";
                shareForceUser = "admin";
                allowedSubnet = "192.168.178.";
            };
            mover.mappings = {
                movies = {
                    path = "/mnt/rackflix/data/Videos/Movies";
                    owner = "admin:users";
                };
                series = {
                    path = "/mnt/rackflix/data/Videos/Serien";
                    owner = "admin:users";
                };
                anime = {
                    path = "/mnt/rackflix/data/Videos/Anime Serien";
                    owner = "admin:users";
                };
                music = {
                    path = "/mnt/rackflix/data/Music";
                    owner = "admin:users";
                };
                stash = {
                    path = "/mnt/rackflix/appdata/.stash/media";
                    owner = "admin:media";
                };
            };
            lidarr = {
                rootFolder = config.my.services.mover.mappings.music.path;
                naming = {
                    artistFolderFormat = "{Artist Name}";
                    standardTrackFormat = "{Album Title}/{track:00} {Track Title}";
                    multiDiscTrackFormat = "{Album Title}/{medium:0}-{track:00} {Track Title}";
                    replaceIllegalCharacters = true;
                };
            };
            ytmMigrate = {
                navidromeUser = "jesse";
                playlists = ["Chill Music" "Favorites" "Music" "Jazz" "Oldies" "Rap" "Mike Dawes" "Guitar"];
            };
            sonarr.libraryDir = "/mnt/rackflix/data/Videos/Serien";
            radarr.libraryDir = "/mnt/rackflix/data/Videos/Movies";
            whisparr.libraryDir = "/mnt/rackflix/appdata/.stash/media";
            qbittorrent.downloadsDir = "/mnt/rackflix/data/downloads";
        };

        services = let
            user = "admin";
            group = "media";
        in {
            nextcloud.home = "/mnt/rackflix/appdata/nextcloud";
            navidrome.settings.MusicFolder = config.my.services.mover.mappings.music.path;
            sonarr = {
                inherit user group;
            };
            radarr = {
                inherit user group;
            };
            whisparr = {
                inherit user group;
            };
            qbittorrent = {
                inherit user group;
            };
        };

        users = {
            groups.media = {};
            users = {
                admin.extraGroups = ["media"];
                stash.extraGroups = ["media"];
                navidrome.extraGroups = ["users"];
            };
        };

        systemd.tmpfiles.rules = [
            "z /mnt/rackflix/data/Videos/Serien 2775 admin media -"
            "z /mnt/rackflix/data/Videos/Movies 2775 admin media -"
            "z /mnt/rackflix/appdata/.stash/media 2775 admin media -"
            "z ${config.my.services.mover.mappings.music.path} 2775 admin users -"
        ];
    };
}
