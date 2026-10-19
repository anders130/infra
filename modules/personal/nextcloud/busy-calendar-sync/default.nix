{
    gitignore = ["__pycache__"];
    den.aspects.nextcloud.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        nc = config.my.services.nextcloud;
        cfg = config.my.services.nextcloudBusyCalendarSync;
        username = cfg.nextcloudUsername;
        unitName = "nextcloud-busy-calendar-sync";
        secretKey = "nextcloud/busyCalendarSync/${username}/appPassword";
        sysUser = "nc-busy-sync-${username}";

        pythonEnv = pkgs.python3.withPackages (ps: [ps.caldav ps.icalendar]);

        syncScript = pkgs.writeShellApplication {
            name = unitName;
            runtimeInputs = [pythonEnv];
            text = ''
                exec python3 ${./sync.py}
            '';
        };

        sourceCalendarsFile = pkgs.writeText "${unitName}-sources.json" (builtins.toJSON cfg.sourceCalendars);
    in {
        options.my.services.nextcloudBusyCalendarSync = {
            nextcloudUsername = lib.mkOption {
                type = lib.types.str;
                description = "Nextcloud account whose calendars get mirrored.";
            };
            destCalendarName = lib.mkOption {
                type = lib.types.str;
                default = "busy";
                description = "Name of the pre-created, shared Nextcloud calendar events get mirrored into.";
            };
            sourceCalendars = lib.mkOption {
                type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
                default = {};
                description = ''
                    Nextcloud calendar name -> per-field sharing policy. Each of
                    summary/location/description maps to "omit" (default, field
                    dropped), "passthrough" (real value copied), or any other
                    string (fixed label, emitted only if the source field is set).
                    A calendar not listed here is never read.
                '';
            };
        };

        config = {
            sops.secrets.${secretKey} = {
                sopsFile = config.my.secretFiles.nextcloud-calendar-sync;
                key = secretKey;
                owner = sysUser;
                mode = "0400";
            };

            users.users.${sysUser} = {
                isSystemUser = true;
                group = sysUser;
            };
            users.groups.${sysUser} = {};

            systemd.services.${unitName} = {
                description = "Mirror ${username}'s Nextcloud calendars into a privacy-filtered busy calendar";
                after = ["phpfpm-nextcloud.service"];
                serviceConfig = {
                    Type = "oneshot";
                    User = sysUser;
                    Group = sysUser;
                    Environment = [
                        "NEXTCLOUD_URL=${nc.url}"
                        "NEXTCLOUD_USER=${username}"
                        "NEXTCLOUD_APP_PASSWORD_FILE=${config.sops.secrets.${secretKey}.path}"
                        "SOURCE_CALENDARS_FILE=${sourceCalendarsFile}"
                        "DEST_CALENDAR_NAME=${cfg.destCalendarName}"
                    ];
                    ExecStart = "${syncScript}/bin/${unitName}";
                };
            };

            systemd.timers.${unitName} = {
                description = "Hourly busy-calendar sync for ${username}";
                wantedBy = ["timers.target"];
                timerConfig = {
                    OnCalendar = "hourly";
                    Persistent = true;
                };
            };
        };
    };
}
