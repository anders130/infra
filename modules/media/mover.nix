{
    den.aspects.mover.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mkOption types;
        cfg = config.my.services.mover;
        incomingPath = cfg.incomingPath;
    in {
        options.my.services.mover = {
            incomingPath = mkOption {
                type = types.str;
                default = "/home/admin/public";
                description = "Drop-folder root; each subfolder name must match a key in `mappings`.";
            };
            mappings = mkOption {
                type = types.attrsOf (types.submodule {
                    options = {
                        path = mkOption {
                            type = types.str;
                            description = "Destination directory this drop-folder's contents get moved into.";
                        };
                        owner = mkOption {
                            type = types.str;
                            description = "chown target passed to rsync, as user:group.";
                        };
                    };
                });
                default = {};
                description = "Drop-folder name -> destination mapping. Empty by default -- a fresh host does nothing until it declares its own targets.";
            };
        };

        config.environment.etc."media-mover/mappings.conf".text =
            cfg.mappings
            |> lib.mapAttrsToList (name: v: "${name}=${v.path}=${v.owner}")
            |> builtins.concatStringsSep "\n";

        config.systemd = {
            tmpfiles.rules = ["d ${incomingPath} 2775 admin users -"];

            services.media-mover = {
                description = "Move files from incoming drop folders to target paths";
                after = ["local-fs.target"];
                serviceConfig = {
                    Type = "oneshot";
                };
                path = with pkgs; [
                    coreutils
                    findutils
                    rsync
                ];
                script = ''
                    INCOMING="${incomingPath}"
                    MAP_FILE="/etc/media-mover/mappings.conf"

                    log() {
                        echo "media-mover: $*"
                        ${pkgs.systemd}/bin/systemd-cat -t media-mover echo "$*"
                    }

                    if [ ! -f "$MAP_FILE" ]; then
                        log "mappings file missing: $MAP_FILE"
                        exit 1
                    fi

                    log "start incoming=$INCOMING"

                    while IFS='=' read -r key dest owner || [ -n "$key" ]; do
                        if [ -z "$key" ] || [ "''${key#\#}" != "$key" ]; then
                            continue
                        fi

                        dest="$(echo "$dest" | tr -d '\r')"
                        owner="$(echo "$owner" | tr -d '\r')"
                        src="$INCOMING/$key"

                        if [ ! -d "$src" ]; then
                            log "skip $key: $src not found"
                            continue
                        fi

                        if [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
                            continue
                        fi

                        if [ ! -d "$dest" ]; then
                            log "target missing: $dest (from $key)"
                            continue
                        fi

                        log "moving $src -> $dest"

                        rsync_args=(-a --remove-source-files --mkpath)
                        if [ -n "$owner" ]; then
                            rsync_args+=(--chown="$owner")
                        fi
                        rsync "''${rsync_args[@]}" "$src"/ "$dest"/

                        find "$src" -type d -empty -delete 2>/dev/null || true
                        log "done $key"
                    done < "$MAP_FILE"

                    log "finished"
                '';
            };

            timers.media-mover = {
                description = "Periodically check for incoming media to move";
                wantedBy = ["timers.target"];
                timerConfig = {
                    OnBootSec = "1min";
                    OnUnitActiveSec = "2min";
                };
            };
        };

        config.security.sudo.extraRules = [
            {
                users = ["admin"];
                commands = [
                    {
                        command = "/run/current-system/sw/bin/systemctl start media-mover.service";
                        options = ["NOPASSWD"];
                    }
                ];
            }
        ];
    };
}
