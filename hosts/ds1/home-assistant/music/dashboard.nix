let
    inherit (import ./_vars.nix) musicPi wohnzimmer zone2 routing;
in {
    den.aspects.ds1.nixos = {
        my.services.home-assistant.dashboards.music-ctrl = {
            title = "Music";
            icon = "mdi:music";
            content = {
                title = "Music";
                views = [
                    {
                        title = "Home";
                        sections = [
                            {
                                type = "grid";
                                cards = [
                                    {
                                        type = "media-control";
                                        entity = musicPi;
                                    }
                                    {
                                        type = "custom:mini-media-player";
                                        entity = wohnzimmer;
                                        hide_unavailable = true;
                                        power_color = true;
                                    }
                                    {
                                        type = "custom:mini-media-player";
                                        entity = zone2;
                                        source = "full";
                                        hide_unavailable = true;
                                        power_color = true;
                                    }
                                    {
                                        type = "custom:mushroom-select-card";
                                        entity = routing;
                                        fill_container = true;
                                        grid_options = {
                                            columns = 12;
                                            rows = 2;
                                        };
                                    }
                                ];
                            }
                        ];
                    }
                ];
            };
        };
    };
}
