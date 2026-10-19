{
    den.aspects.ds1.nixos = {lib, ...}: let
        inherit (lib) filter;

        zones = ["1" "2" "3" "4" "5" "6"];
        valveEntity = n: "valve.garden_controller_valve_zone_${n}";

        gardenLight = "light.garden_controller_garden_light";
        waterfallPump = "switch.garden_controller_waterfall_pump";
        weather = "weather.forecast_home";
        teichDuration = "input_number.garden_teich_duration";
        potsDuration = "input_number.garden_pots_duration";
        teichTime = "input_datetime.garden_teich_time";
        potsTime = "input_datetime.garden_pots_time";

        valveTile = entity: name: {
            type = "tile";
            inherit entity name;
            icon = "mdi:sprinkler-variant";
            tap_action.action = "toggle";
        };

        schedCard = scriptEntity: name: timeEntity: durEntity: mult: {
            type = "custom:mushroom-template-card";
            primary = name;
            secondary = ''
                {%- set total = (states('${durEntity}') | int) * ${toString mult} %}
                {%- if is_state('${scriptEntity}', 'running') %}
                {%- set started = state_attr('${scriptEntity}', 'last_triggered') %}
                {%- set elapsed = ((now() - started).total_seconds() / 60) | int %}
                ~{{ [total - elapsed, 0] | max }} min remaining
                {%- else %}{{ states('${timeEntity}')[:5] }} — ~{{ total }} min{%- endif -%}
            '';
            icon = "mdi:sprinkler";
            icon_color = ''
                {%- if is_state('${scriptEntity}', 'running') %}blue{%- else %}grey{%- endif -%}
            '';
            tap_action = {
                action = "more-info";
                entity = timeEntity;
            };
            hold_action = {
                action = "more-info";
                entity = durEntity;
            };
            card_mod.style = ''
                ha-card {
                    {% if is_state('${scriptEntity}', 'running') %}
                    background: rgba(var(--rgb-primary-color), 0.15) !important;
                    {% endif %}
                }
            '';
        };

        teichSchedCard = schedCard "script.garden_teich_water" "Teich" teichTime teichDuration 3;
        potsSchedCard = schedCard "script.garden_pots_water" "Töpfe + Hochbeet" potsTime potsDuration 2;

        openValve = entity: {
            action = "valve.open_valve";
            target.entity_id = entity;
        };
        closeValve = entity: {
            action = "valve.close_valve";
            target.entity_id = entity;
        };
        teichDelay = {delay.minutes = "{{ states('${teichDuration}') | int }}";};
        potsDelay = {delay.minutes = "{{ states('${potsDuration}') | int }}";};

        notFrost = {
            condition = "numeric_state";
            entity_id = weather;
            attribute = "temperature";
            above = 3;
        };
        notRain = {
            condition = "not";
            conditions = [
                {
                    condition = "state";
                    entity_id = weather;
                    state = ["rainy" "pouring" "lightning-rainy" "snowy-rainy"];
                }
            ];
        };
        sunIsUp = {
            condition = "sun";
            after = "sunrise";
            before = "sunset";
        };
        notWinter = {
            condition = "template";
            value_template = "{{ now().month not in [11, 12, 1, 2] }}";
        };
    in {
        my.services.home-assistant.dashboards.garden-ctrl = {
            title = "Garden";
            icon = "mdi:sprinkler";
            content = {
                title = "Garden";
                views = [
                    {
                        title = "Control";
                        path = "garden";
                        cards = [
                            {
                                type = "heading";
                                heading = "Lights & Pump";
                            }
                            {
                                type = "grid";
                                columns = 2;
                                square = false;
                                cards = [
                                    {
                                        type = "tile";
                                        entity = waterfallPump;
                                        name = "Waterfall Pump";
                                        icon = "mdi:water-pump";
                                    }
                                    {
                                        type = "tile";
                                        entity = gardenLight;
                                        name = "Garden Light";
                                        icon = "mdi:outdoor-lamp";
                                    }
                                ];
                            }
                            {
                                type = "heading";
                                heading = "Schedule";
                            }
                            teichSchedCard
                            potsSchedCard
                            {
                                type = "heading";
                                heading = "Valve Zones";
                            }
                            {
                                type = "grid";
                                columns = 2;
                                square = false;
                                cards = [
                                    (valveTile (valveEntity "1") "Teich 1")
                                    (valveTile (valveEntity "6") "Blumen Vorne")
                                    (valveTile (valveEntity "2") "Teich 2")
                                    (valveTile (valveEntity "5") "Blumentöpfe")
                                    (valveTile (valveEntity "3") "Teich 3")
                                    (valveTile (valveEntity "4") "Hochbeet")
                                ];
                            }
                        ];
                    }
                ];
            };
        };

        services.home-assistant.config = {
            input_number.garden_teich_duration = {
                name = "Teich zone duration";
                min = 1;
                max = 30;
                step = 1;
                initial = 5;
                unit_of_measurement = "min";
                icon = "mdi:timer";
            };

            input_number.garden_pots_duration = {
                name = "Töpfe + Hochbeet duration";
                min = 1;
                max = 60;
                step = 1;
                initial = 10;
                unit_of_measurement = "min";
                icon = "mdi:timer";
            };

            input_datetime.garden_teich_time = {
                name = "Teich watering time";
                has_time = true;
                has_date = false;
                initial = "08:00:00";
            };

            input_datetime.garden_pots_time = {
                name = "Töpfe + Hochbeet time";
                has_time = true;
                has_date = false;
                initial = "17:00:00";
            };

            homeassistant.packages.garden.automation =
                (map (n: {
                    id = "garden_valve_zone_${n}_exclusive";
                    alias = "Garden - Zone ${n} exclusive";
                    trigger = [
                        {
                            trigger = "state";
                            entity_id = valveEntity n;
                            to = "open";
                        }
                    ];
                    action = [
                        {
                            action = "valve.close_valve";
                            target.entity_id = map valveEntity (filter (m: m != n) zones);
                        }
                    ];
                })
                zones)
                ++ [
                    {
                        id = "garden_waterfall_sunrise";
                        alias = "Garden - Waterfall on at sunrise";
                        trigger = [
                            {
                                trigger = "sun";
                                event = "sunrise";
                            }
                        ];
                        condition = [notFrost];
                        action = [
                            {
                                action = "switch.turn_on";
                                target.entity_id = waterfallPump;
                            }
                        ];
                    }
                    {
                        id = "garden_waterfall_frost_clear";
                        alias = "Garden - Waterfall on when frost clears";
                        trigger = [
                            {
                                trigger = "numeric_state";
                                entity_id = weather;
                                attribute = "temperature";
                                above = 3;
                            }
                        ];
                        condition = [sunIsUp];
                        action = [
                            {
                                action = "switch.turn_on";
                                target.entity_id = waterfallPump;
                            }
                        ];
                    }
                    {
                        id = "garden_waterfall_sunset";
                        alias = "Garden - Waterfall off at sunset";
                        trigger = [
                            {
                                trigger = "sun";
                                event = "sunset";
                            }
                        ];
                        action = [
                            {
                                action = "switch.turn_off";
                                target.entity_id = waterfallPump;
                            }
                        ];
                    }
                    {
                        id = "garden_frost_protect";
                        alias = "Garden - Frost protection";
                        trigger = [
                            {
                                trigger = "numeric_state";
                                entity_id = weather;
                                attribute = "temperature";
                                below = 3;
                            }
                        ];
                        action = [
                            {
                                action = "switch.turn_off";
                                target.entity_id = waterfallPump;
                            }
                            {
                                action = "valve.close_valve";
                                target.entity_id = map valveEntity zones;
                            }
                            {
                                action = "script.turn_off";
                                target.entity_id = ["script.garden_teich_water" "script.garden_pots_water"];
                            }
                        ];
                    }
                    {
                        id = "garden_light_sunset";
                        alias = "Garden - Light on at sunset";
                        trigger = [
                            {
                                trigger = "sun";
                                event = "sunset";
                            }
                        ];
                        action = [
                            {
                                action = "light.turn_on";
                                target.entity_id = gardenLight;
                            }
                        ];
                    }
                    {
                        id = "garden_light_midnight";
                        alias = "Garden - Light off at midnight";
                        trigger = [
                            {
                                trigger = "time";
                                at = "00:00:00";
                            }
                        ];
                        action = [
                            {
                                action = "light.turn_off";
                                target.entity_id = gardenLight;
                            }
                        ];
                    }
                    {
                        id = "garden_teich_schedule";
                        alias = "Garden - Teich watering";
                        trigger = [
                            {
                                trigger = "time";
                                at = teichTime;
                            }
                        ];
                        condition = [notFrost notRain notWinter];
                        action = [
                            {
                                action = "script.turn_on";
                                target.entity_id = "script.garden_teich_water";
                            }
                        ];
                    }
                    {
                        id = "garden_pots_schedule";
                        alias = "Garden - Blumentöpfe + Hochbeet watering";
                        trigger = [
                            {
                                trigger = "time";
                                at = potsTime;
                            }
                        ];
                        condition = [notFrost notWinter];
                        action = [
                            {
                                action = "script.turn_on";
                                target.entity_id = "script.garden_pots_water";
                            }
                        ];
                    }
                    {
                        id = "garden_winter_start";
                        alias = "Garden - Winter first frost shutdown";
                        trigger = [
                            {
                                trigger = "numeric_state";
                                entity_id = weather;
                                attribute = "temperature";
                                below = 0;
                            }
                        ];
                        condition = [
                            {
                                condition = "template";
                                value_template = "{{ now().month in [10, 11, 12] }}";
                            }
                        ];
                        action = [
                            {
                                action = "switch.turn_off";
                                target.entity_id = waterfallPump;
                            }
                            {
                                action = "valve.close_valve";
                                target.entity_id = map valveEntity zones;
                            }
                            {
                                action = "script.turn_off";
                                target.entity_id = [
                                    "script.garden_teich_water"
                                    "script.garden_pots_water"
                                ];
                            }
                            {
                                action = "notify.notify";
                                data = {
                                    title = "Garden - Winter";
                                    message = "First frost — shut off main water supply.";
                                };
                            }
                        ];
                    }
                    {
                        id = "garden_spring_remind";
                        alias = "Garden - Spring water reminder";
                        trigger = [
                            {
                                trigger = "time";
                                at = "09:00:00";
                            }
                        ];
                        condition = [
                            {
                                condition = "template";
                                value_template = "{{ now().month == 2 and now().day == 15 }}";
                            }
                        ];
                        action = [
                            {
                                action = "notify.notify";
                                data = {
                                    title = "Garden - Spring";
                                    message = "Mid-February — turn main water supply back on.";
                                };
                            }
                        ];
                    }
                ];

            script = {
                garden_teich_water = {
                    alias = "Water Teich zones";
                    mode = "single";
                    sequence = [
                        (openValve (valveEntity "1"))
                        teichDelay
                        (closeValve (valveEntity "1"))
                        (openValve (valveEntity "5"))
                        teichDelay
                        (closeValve (valveEntity "5"))
                        (openValve (valveEntity "3"))
                        teichDelay
                        (closeValve (valveEntity "3"))
                    ];
                };

                garden_pots_water = {
                    alias = "Water Blumentöpfe + Hochbeet";
                    mode = "single";
                    sequence = [
                        (openValve (valveEntity "4"))
                        potsDelay
                        (closeValve (valveEntity "4"))
                        (openValve (valveEntity "6"))
                        potsDelay
                        (closeValve (valveEntity "6"))
                    ];
                };
            };
        };
    };
}
