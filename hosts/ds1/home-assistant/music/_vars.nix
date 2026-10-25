let
    musicPi = "media_player.music_pi";
    wohnzimmer = "media_player.wohnzimmer";
    zone2 = "media_player.wohnzimmer_zone2";
    routing = "input_select.music_pi_routing";

    srcMusicPi = "Music-Pi";
    srcSync = "Main Zone Sync";
    srcTV = "TV";
    srcNonMusic = "'${srcTV}', 'HDMI1', 'HDMI2', 'HDMI3', 'HDMI4', 'HDMI5', 'HDMI6', 'Amazon FireTV'";

    optWohnzimmer = "Wohnzimmer";
    optEsszimmer = "Esszimmer";
    optBeide = "Beide";

    routingIs = opt: {
        condition = "state";
        entity_id = routing;
        state = opt;
    };
    volSet = target: {
        action = "media_player.volume_set";
        target.entity_id = target;
        data.volume_level = "{{ vol }}";
    };
    turnOn = target: {
        action = "media_player.turn_on";
        target.entity_id = target;
    };
    selectSource = target: source: {
        action = "media_player.select_source";
        target.entity_id = target;
        data.source = source;
    };
    runScript = name: {
        action = "script.turn_on";
        target.entity_id = "script.${name}";
    };

    routeDispatch = w: e: b: {
        choose = [
            {
                conditions = [(routingIs optWohnzimmer)];
                sequence = w;
            }
            {
                conditions = [(routingIs optEsszimmer)];
                sequence = e;
            }
            {
                conditions = [(routingIs optBeide)];
                sequence = b;
            }
        ];
    };

    wohnzimmerSafe = {
        condition = "template";
        value_template = "{{ state_attr('${wohnzimmer}', 'source') not in [${srcNonMusic}] and (states('${wohnzimmer}') != 'playing' or state_attr('${wohnzimmer}', 'source') == '${srcMusicPi}') }}";
    };
    zone2Safe = {
        condition = "template";
        value_template = "{{ states('${zone2}') != 'playing' or state_attr('${zone2}', 'source') in ['${srcMusicPi}', '${srcSync}'] }}";
    };
in {
    inherit musicPi wohnzimmer zone2 routing;
    inherit srcMusicPi srcSync srcTV srcNonMusic;
    inherit optWohnzimmer optEsszimmer optBeide;
    inherit routingIs volSet turnOn selectSource runScript routeDispatch;
    inherit wohnzimmerSafe zone2Safe;
}
