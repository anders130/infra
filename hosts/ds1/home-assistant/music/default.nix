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
        ;
in {
    den.aspects.ds1.nixos = {
        services.home-assistant.config = {
            homeassistant.customize = {
                ${wohnzimmer} = {
                    friendly_name = optWohnzimmer;
                    source_list = [srcMusicPi srcTV];
                };
                ${zone2}.source_list = [srcMusicPi srcSync];
            };

            input_select.music_pi_routing = {
                name = "Music-Pi Routing";
                options = [optWohnzimmer optEsszimmer optBeide];
                icon = "mdi:speaker-multiple";
            };
        };
    };
}
