{
    den.aspects.terraria.nixos = {
        config,
        pkgs,
        ...
    }: let
        user = "root";
        group = "root";
        stateDir = config.services.gameStatusHttp.playerStateDir;
    in {
        sops.secrets.terraria = {
            inherit group;
            owner = user;
            sopsFile = config.my.secretFiles.terraria;
            format = "dotenv";
        };
        my.services.ntfy = {
            targets.terraria = {
                secretFile = config.sops.secrets.terraria.path;
                authHash = "$2b$10$tlJUsC2NQlQZrWnxSKoLje9RudurxUUZ9TWAyXX8yyKLZ97DUgzcW";
            };
            sources.terraria = {
                inherit user group;
                wantedBy = ["terraria.service"];
                after = ["terraria.service"];
                partOf = ["terraria.service"];
                script = runtimeInputs:
                    pkgs.writeShellApplication {
                        inherit runtimeInputs;
                        name = "notify-terraria";
                        text = ''
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
                                players_json > ${stateDir}/terraria.json.tmp
                                chmod 644 ${stateDir}/terraria.json.tmp
                                mv ${stateDir}/terraria.json.tmp ${stateDir}/terraria.json
                            }

                            declare -A online_players
                            write_player_state

                            # No log file -- journald has the console output instead.
                            journalctl -u terraria -f -o cat -n0 | while IFS= read -r line; do
                                if echo "$line" | grep -qE '^.+ has joined\.$'; then
                                    player=$(echo "$line" | sed -nE 's/^(.+) has joined\.$/\1/p')
                                    if [ -z "''${online_players[$player]+x}" ]; then
                                        online_players["$player"]=1
                                        write_player_state
                                        message "$player joined the Terraria server"
                                    fi
                                fi
                                if echo "$line" | grep -qE '^.+ has left\.$'; then
                                    player=$(echo "$line" | sed -nE 's/^(.+) has left\.$/\1/p')
                                    if [ -n "''${online_players[$player]+x}" ]; then
                                        unset "online_players[$player]"
                                        write_player_state
                                        message "$player left the Terraria server"
                                    fi
                                fi
                            done
                        '';
                    };
            };
        };
    };
}
