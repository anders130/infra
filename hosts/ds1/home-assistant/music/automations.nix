let
    inherit
        (import ./_vars.nix)
        musicPi
        wohnzimmer
        zone2
        routing
        volSet
        runScript
        routeDispatch
        ;
in {
    den.aspects.ds1.nixos = {
        services.home-assistant.config.homeassistant.packages.music.automation = [
            {
                id = "music_pi_routing";
                alias = "Music-Pi Routing";
                trigger = [
                    {
                        trigger = "state";
                        entity_id = routing;
                    }
                ];
                action = [(runScript "music_pi_auto_route")];
            }
            {
                id = "music_pi_volume_relay";
                alias = "Music-Pi volume → Yamaha";
                trigger = [
                    {
                        trigger = "state";
                        entity_id = musicPi;
                        attribute = "volume_level";
                    }
                    {
                        trigger = "state";
                        entity_id = musicPi;
                        to = "playing";
                    }
                ];
                condition = [
                    {
                        condition = "template";
                        value_template = "{{ state_attr('${musicPi}', 'volume_level') is not none }}";
                    }
                ];
                action = [
                    {variables.vol = "{{ (state_attr('${musicPi}', 'volume_level') | float(0)) ** 0.5 * 0.8 }}";}
                    (routeDispatch
                    [(volSet wohnzimmer)]
                    [(volSet zone2)]
                    [(volSet wohnzimmer) (volSet zone2)])
                ];
            }
            {
                id = "music_pi_auto_on";
                alias = "MusicCast auto-on when Music-Pi plays";
                trigger = [
                    {
                        trigger = "state";
                        entity_id = musicPi;
                        to = "playing";
                    }
                ];
                action = [(runScript "music_pi_soft_on")];
            }
        ];
    };
}
