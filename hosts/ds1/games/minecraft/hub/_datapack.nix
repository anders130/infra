{
    pkgs,
    lib,
    serverInfos,
}: let
    mkInfoCmd = s: ''
        kill @e[tag=sinfo_display_${s.serverName}]
        execute at @e[type=minecraft:marker,tag=portal_info_${s.serverName},limit=1] run summon minecraft:text_display ~ ~2.0 ~ {text:'{"text":"","extra":[{"text":"${s.displayName}","bold":true,"color":"${s.color}"},{"text":"\\n${s.subLine}","color":"gray"},{"text":"\\n${s.motdLine}","color":"white"},{"text":"\\n? online","color":"dark_gray"}]}',alignment:"center",billboard:"center",Tags:["sinfo_display_${s.serverName}","server_display"]}
    '';
in
    pkgs.stdenvNoCC.mkDerivation {
        name = "hub-spawn-on-join";
        dontUnpack = true;
        buildPhase = ''
                    mkdir -p data/minecraft/tags/function data/hub_spawn/function

                    echo '{"values":["hub_spawn:load"]}' > data/minecraft/tags/function/load.json
                    echo '{"values":["hub_spawn:tick"]}' > data/minecraft/tags/function/tick.json

                    cat > data/hub_spawn/function/load.mcfunction << 'EOF'
            scoreboard objectives add hub_leave_stat minecraft.custom:minecraft.leave_game
            scoreboard objectives add hub_leave_saved dummy
            ${lib.concatMapStrings mkInfoCmd serverInfos}
            EOF

                    cat > data/hub_spawn/function/tick.mcfunction << 'EOF'
            execute as @a unless score @s hub_leave_saved = @s hub_leave_stat run function hub_spawn:on_join
            execute as @a run scoreboard players operation @s hub_leave_saved = @s hub_leave_stat
            EOF

                    cat > data/hub_spawn/function/on_join.mcfunction << 'EOF'
            execute at @e[type=minecraft:marker,tag=hub_spawn,limit=1] run tp @s ~ ~ ~
            EOF
        '';
        installPhase = ''
            mkdir -p $out
            cp -r data $out/
            printf '{"pack":{"description":"Teleport to spawn on join","pack_format":48,"supported_formats":[45,81]}}' > $out/pack.mcmeta
        '';
    }
