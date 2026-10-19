{
    den.aspects.ds1.nixos = let
        pins = {
            ultrasonicTrigger = 5;
            ultrasonicEcho = 18;
            remote = 23;
        };
        pulseLength = "1s";
        pulsePause = "1s";
    in {
        my.services.esphome.firmwareConfigs.garagentor-volvo = {
            esphome = {
                name = "garagentor-volvo";
                friendly_name = "Garagentor Volvo";
            };
            esp32 = {
                board = "esp32dev";
                framework.type = "arduino";
            };
            wifi = {
                ssid = "!secret garage_wifi_ssid";
                password = "!secret garage_wifi_password";
                power_save_mode = "none";
                ap = {
                    ssid = "Garagentor Volvo Fallback";
                    password = "!secret ap_password";
                };
            };
            logger = {};
            captive_portal = {};
            api.encryption.key = "!secret api_encryption_key";
            ota = [
                {
                    platform = "esphome";
                    password = "!secret ota_password";
                }
            ];

            globals = let
                mkGlobal = id: type: initial_value: {
                    inherit id type initial_value;
                    restore_value = false;
                };
            in [
                (mkGlobal "last_distance" "float" "NAN")
                (mkGlobal "direction" "int" "0")
                (mkGlobal "last_direction" "int" "1")
                (mkGlobal "travel_start" "uint32_t" "0")
                (mkGlobal "last_motion" "uint32_t" "0")
            ];

            number = let
                mkCalibration = {
                    id,
                    name,
                    initial_value,
                    min_value,
                    max_value,
                    unit_of_measurement,
                    step ? 1,
                }: {
                    platform = "template";
                    optimistic = true;
                    restore_value = true;
                    entity_category = "config";
                    inherit id name initial_value min_value max_value unit_of_measurement step;
                };
            in
                map mkCalibration [
                    {
                        id = "open_below";
                        name = "Open Below";
                        unit_of_measurement = "cm";
                        min_value = 5;
                        max_value = 400;
                        initial_value = 40;
                    }
                    {
                        id = "closed_above";
                        name = "Closed Above";
                        unit_of_measurement = "cm";
                        min_value = 5;
                        max_value = 400;
                        initial_value = 150;
                    }
                    {
                        id = "move_delta";
                        name = "Movement Threshold";
                        unit_of_measurement = "cm";
                        min_value = 1;
                        max_value = 50;
                        initial_value = 3;
                    }
                    {
                        id = "settle_time";
                        name = "Movement Settle Time";
                        unit_of_measurement = "s";
                        min_value = 1;
                        max_value = 30;
                        initial_value = 3;
                        step = 0.5;
                    }
                ];

            switch = [
                {
                    platform = "gpio";
                    pin = {
                        number = pins.remote;
                        inverted = false;
                    };
                    id = "remote_relay";
                    internal = true;
                    restore_mode = "ALWAYS_OFF";
                }
            ];

            script = let
                mkPulses = id: count: {
                    inherit id;
                    mode = "single";
                    "then" = [
                        {
                            repeat = {
                                inherit count;
                                "then" = [
                                    {"script.execute" = "pulse_remote";}
                                    {"script.wait" = "pulse_remote";}
                                    {delay = pulsePause;}
                                ];
                            };
                        }
                    ];
                };
            in [
                {
                    id = "pulse_remote";
                    mode = "single";
                    "then" = [
                        {"switch.turn_on" = "remote_relay";}
                        {delay = pulseLength;}
                        {"switch.turn_off" = "remote_relay";}
                    ];
                }
                (mkPulses "reverse_remote" 2)
                (mkPulses "reverse_idle_remote" 3)
            ];

            sensor = [
                {
                    platform = "ultrasonic";
                    id = "door_distance";
                    name = "Door Distance";
                    trigger_pin = pins.ultrasonicTrigger;
                    echo_pin = pins.ultrasonicEcho;
                    update_interval = "500ms";
                    timeout = "4m";
                    unit_of_measurement = "cm";
                    accuracy_decimals = 1;
                    entity_category = "diagnostic";
                    filters = [
                        {filter_out = "nan";}
                        {multiply = 100;}
                        {
                            median = {
                                window_size = 3;
                                send_every = 1;
                                send_first_at = 1;
                            };
                        }
                    ];
                    on_value = [
                        {
                            lambda = ''
                                if (std::isnan(x)) return;
                                float previous = id(last_distance);
                                uint32_t now = millis();
                                id(last_distance) = x;
                                if (!std::isnan(previous) && fabsf(x - previous) >= id(move_delta).state) {
                                  if (id(direction) == 0) { id(travel_start) = now; }
                                  id(direction) = x > previous ? -1 : 1;
                                  id(last_direction) = id(direction);
                                  id(last_motion) = now;
                                } else if (id(direction) != 0 && now - id(last_motion) > (uint32_t) (id(settle_time).state * 1000)) {
                                  id(direction) = 0;
                                  id(travel_duration).publish_state((now - id(travel_start)) / 1000.0f);
                                }
                                float span = id(closed_above).state - id(open_below).state;
                                auto *door = id(tor);
                                door->position = span > 0 ? clamp((id(closed_above).state - x) / span, 0.0f, 1.0f) : 0.0f;
                                door->current_operation = id(direction) == 1 ? COVER_OPERATION_OPENING : (id(direction) == -1 ? COVER_OPERATION_CLOSING : COVER_OPERATION_IDLE);
                                door->publish_state();
                            '';
                        }
                    ];
                }
                {
                    platform = "template";
                    id = "travel_duration";
                    name = "Last Travel Duration";
                    unit_of_measurement = "s";
                    device_class = "duration";
                    state_class = "measurement";
                    accuracy_decimals = 1;
                    entity_category = "diagnostic";
                    update_interval = "never";
                }
                {
                    platform = "wifi_signal";
                    name = "WiFi Signal";
                    update_interval = "60s";
                    entity_category = "diagnostic";
                }
                {
                    platform = "uptime";
                    name = "Uptime";
                    entity_category = "diagnostic";
                }
            ];

            cover = [
                {
                    platform = "template";
                    id = "tor";
                    name = "";
                    device_class = "garage";
                    assumed_state = true;
                    optimistic = false;
                    open_action = [
                        {
                            lambda = ''
                                auto *door = id(tor);
                                if (door->position >= 0.999f || id(direction) == 1) return;
                                if (id(direction) == -1) { id(reverse_remote).execute(); return; }
                                if (door->position <= 0.001f || id(last_direction) == -1) { id(pulse_remote).execute(); return; }
                                id(reverse_idle_remote).execute();
                            '';
                        }
                    ];
                    close_action = [
                        {
                            lambda = ''
                                auto *door = id(tor);
                                if (door->position <= 0.001f || id(direction) == -1) return;
                                if (id(direction) == 1) { id(reverse_remote).execute(); return; }
                                if (door->position >= 0.999f || id(last_direction) == 1) { id(pulse_remote).execute(); return; }
                                id(reverse_idle_remote).execute();
                            '';
                        }
                    ];
                    stop_action = [
                        {
                            lambda = ''
                                if (id(direction) != 0) { id(pulse_remote).execute(); }
                            '';
                        }
                    ];
                }
            ];

            button = [
                {
                    platform = "template";
                    name = "Pulse Remote";
                    entity_category = "diagnostic";
                    on_press = [{"script.execute" = "pulse_remote";}];
                }
                {
                    platform = "restart";
                    name = "Restart";
                    entity_category = "diagnostic";
                }
            ];
        };
    };
}
