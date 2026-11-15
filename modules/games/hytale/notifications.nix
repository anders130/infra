{
    den.aspects.hytale.nixos = {
        config,
        pkgs,
        ...
    }: let
        logDir = "/var/lib/hytale/data/logs";
        stateDir = config.services.gameStatusHttp.playerStateDir;
        hytaleService = "podman-hytale.service";
        user = "root";
        group = "root";
    in {
        config = {
            sops.secrets.hytale = {
                inherit group;
                owner = user;
                sopsFile = config.my.secretFiles.hytale;
                format = "dotenv";
            };
            my.services.ntfy = {
                targets.hytale = {
                    secretFile = config.sops.secrets.hytale.path;
                    authHash = "$2b$10$sTzBIrsXTj1ryvIsJ5JqtOQy4GPeF9BDQG05TnCmaRXwYCA.iS2VC";
                };
                sources.hytale = {
                    inherit user group;
                    wantedBy = [hytaleService];
                    after = [hytaleService];
                    partOf = [hytaleService];
                    script = runtimeInputs:
                        pkgs.writeShellApplication {
                            inherit runtimeInputs;
                            name = "notify-hytale";
                            text = ''
                                get_latest_log() {
                                    find ${logDir} -maxdepth 1 -type f -name '*_server.log' -print \
                                    | sort | tail -n1
                                }

                                # No jq available here -- hand-escape instead.
                                players_json() {
                                    local first=1 player
                                    printf '['
                                    for player in "''${!online_players[@]}"; do
                                        [ "$first" -eq 1 ] || printf ','
                                        first=0
                                        local escaped="''${player//\\/\\\\}"
                                        escaped="''${escaped//\"/\\\"}"
                                        printf '"%s"' "$escaped"
                                    done
                                    printf ']'
                                }

                                write_player_state() {
                                    mkdir -p ${stateDir}
                                    chmod 755 ${stateDir}
                                    players_json > ${stateDir}/podman-hytale.json.tmp
                                    chmod 644 ${stateDir}/podman-hytale.json.tmp
                                    mv ${stateDir}/podman-hytale.json.tmp ${stateDir}/podman-hytale.json
                                }

                                follow_log() {
                                    local logfile="$1"
                                    declare -A online_players
                                    write_player_state

                                    while IFS= read -r line; do
                                        if echo "$line" | grep -q "Player '.*' joined world"; then
                                            player=$(echo "$line" | sed -nE "s/.*Player '([^']+)'.*/\1/p")
                                            if [ -z "''${online_players[$player]+x}" ]; then
                                                online_players["$player"]=1
                                                write_player_state
                                                message "$player joined the Hytale server"
                                            fi
                                        fi
                                        if echo "$line" | grep -q "Removing player '"; then
                                            player=$(echo "$line" | sed -nE "s/.*Removing player '([^']+)'.*/\1/p")
                                            if [ -n "''${online_players[$player]+x}" ]; then
                                                unset "online_players[$player]"
                                                write_player_state
                                                message "$player left the Hytale server"
                                            fi
                                        fi
                                    done < <(tail -n0 -F "$logfile")
                                }

                                while true; do
                                    logfile=$(get_latest_log)
                                    [ -z "$logfile" ] && sleep 5 && continue
                                    follow_log "$logfile"
                                done
                            '';
                        };
                };
            };
        };
    };
}
