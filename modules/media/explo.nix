{
    den.aspects.explo.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        cfg = config.my.services.explo;

        explo-go = pkgs.buildGoModule {
            pname = "explo-unwrapped";
            version = "0.11.5";
            src = pkgs.fetchFromGitHub {
                owner = "LumePart";
                repo = "Explo";
                rev = "v0.11.5";
                hash = "sha256-A3ikFH0/C/dat1pf7t1Gp6bfitmbPHK+RKVzqsLzjc0=";
            };
            vendorHash = "sha256-jTvxv0cyE/+BNkrajIj8E3xlftq+PCtGbmz+P3IuMFw=";
            subPackages = ["src/main"];
            postInstall = ''
                mv $out/bin/main $out/bin/explo-unwrapped
                install -Dm644 src/downloader/youtube_music/search_ytmusic.py \
                    $out/share/explo/search_ytmusic.py
            '';
        };

        pythonEnv = pkgs.python3.withPackages (ps: [ps.ytmusicapi]);

        explo = pkgs.writeShellScriptBin "explo" ''
            export PATH="${lib.makeBinPath [pythonEnv pkgs.ffmpeg-headless pkgs.yt-dlp]}:$PATH"
            tmpdir=$(mktemp -d)
            trap "rm -rf $tmpdir" EXIT
            ln -s ${explo-go}/share/explo/search_ytmusic.py "$tmpdir/search_ytmusic.py"
            cd "$tmpdir"
            exec ${explo-go}/bin/explo-unwrapped "$@"
        '';
    in {
        options.my.services.explo = {
            listenbrainzUser = mkOption {type = types.str;};
            systemUrl = mkOption {
                type = types.str;
                default = "http://127.0.0.1:4533";
            };
            systemUsername = mkOption {type = types.str;};
            downloadDir = mkOption {type = types.str;};
        };

        config = {
            sops.secrets."explo/system_password" = {
                sopsFile = config.my.secretFiles.explo;
            };

            sops.templates."explo.env" = {
                content = ''
                    DISCOVERY_SERVICE=listenbrainz
                    LISTENBRAINZ_USER=${cfg.listenbrainzUser}
                    LISTENBRAINZ_DISCOVERY=playlist
                    EXPLO_SYSTEM=subsonic
                    SYSTEM_URL=${cfg.systemUrl}
                    SYSTEM_USERNAME=${cfg.systemUsername}
                    ADMIN_SYSTEM_USERNAME=${cfg.systemUsername}
                    SYSTEM_PASSWORD=${config.sops.placeholder."explo/system_password"}
                    ADMIN_SYSTEM_PASSWORD=${config.sops.placeholder."explo/system_password"}
                    DOWNLOAD_DIR=${cfg.downloadDir}
                    DOWNLOAD_SERVICES=youtube
                    TRACK_EXTENSION=opus
                    PUBLIC_PLAYLIST=true
                    LOG_LEVEL=INFO
                '';
            };

            systemd.services.explo = {
                description = "Explo music discovery";
                serviceConfig = {
                    Type = "oneshot";
                    ExecStart = "${explo}/bin/explo --config ${config.sops.templates."explo.env".path} --playlist daily-jams";
                };
            };

            systemd.timers.explo = {
                wantedBy = ["timers.target"];
                timerConfig = {
                    OnCalendar = "daily";
                    Persistent = true;
                };
            };
        };
    };
}
