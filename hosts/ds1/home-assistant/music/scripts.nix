let
    inherit
        (import ./_vars.nix)
        wohnzimmer
        zone2
        srcMusicPi
        srcSync
        srcTV
        optWohnzimmer
        optEsszimmer
        optBeide
        routingIs
        turnOn
        selectSource
        runScript
        routeDispatch
        wohnzimmerSafe
        zone2Safe
        ;
in {
    den.aspects.ds1.nixos = {
        services.home-assistant.config.script = {
            music_pi_wohnzimmer = {
                alias = "Music-Pi → ${optWohnzimmer}";
                sequence = [
                    (turnOn wohnzimmer)
                    (selectSource wohnzimmer srcMusicPi)
                    {
                        "if" = [
                            {
                                condition = "state";
                                entity_id = zone2;
                                attribute = "source";
                                state = srcMusicPi;
                            }
                        ];
                        "then" = [(selectSource zone2 srcSync)];
                    }
                ];
            };

            music_pi_esszimmer = {
                alias = "Music-Pi → ${optEsszimmer}";
                sequence = [
                    (turnOn zone2)
                    (selectSource zone2 srcMusicPi)
                    {
                        "if" = [
                            {
                                condition = "state";
                                entity_id = wohnzimmer;
                                attribute = "source";
                                state = srcMusicPi;
                            }
                        ];
                        "then" = [(selectSource wohnzimmer srcTV)];
                    }
                ];
            };

            music_pi_beide = {
                alias = "Music-Pi → ${optBeide}";
                sequence = [
                    (turnOn wohnzimmer)
                    (selectSource wohnzimmer srcMusicPi)
                    (turnOn zone2)
                    (selectSource zone2 srcSync)
                ];
            };

            music_pi_soft_on = {
                alias = "Music-Pi soft auto-on";
                sequence = [
                    {
                        choose = [
                            {
                                conditions = [(routingIs optWohnzimmer) wohnzimmerSafe];
                                sequence = [(runScript "music_pi_wohnzimmer")];
                            }
                            {
                                conditions = [(routingIs optEsszimmer) zone2Safe];
                                sequence = [(runScript "music_pi_esszimmer")];
                            }
                            {
                                conditions = [(routingIs optBeide)];
                                sequence = [
                                    {
                                        "if" = [wohnzimmerSafe];
                                        "then" = [(turnOn wohnzimmer) (selectSource wohnzimmer srcMusicPi)];
                                    }
                                    {
                                        "if" = [zone2Safe];
                                        "then" = [(turnOn zone2) (selectSource zone2 srcSync)];
                                    }
                                ];
                            }
                        ];
                    }
                ];
            };

            music_pi_auto_route = {
                alias = "Music-Pi → Auto Route";
                sequence = [
                    (routeDispatch
                    [(runScript "music_pi_wohnzimmer")]
                    [(runScript "music_pi_esszimmer")]
                    [(runScript "music_pi_beide")])
                ];
            };
        };
    };
}
