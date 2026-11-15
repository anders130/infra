{
    den.aspects.ds1.nixos = {
        my.services.esphome.firmwareConfigs.garden-ctrl = {
            esphome = {
                name = "garden-ctrl";
                friendly_name = "Garden Controller";
            };
            esp32 = {
                board = "esp32dev";
                framework.type = "arduino";
            };
            wifi = {
                ssid = "!secret wifi_ssid";
                password = "!secret wifi_password";
                ap = {
                    ssid = "Garden Ctrl Fallback";
                    password = "!secret ap_password";
                };
            };
            logger = {};
            api.encryption.key = "!secret api_encryption_key";
            ota = [
                {
                    platform = "esphome";
                    password = "!secret ota_password";
                }
            ];
            switch = let
                valveSwitch = pin: n: {
                    platform = "gpio";
                    inherit pin;
                    id = "valve_zone_${n}_sw";
                    internal = true;
                    restore_mode = "RESTORE_DEFAULT_OFF";
                };
            in [
                (valveSwitch 25 "1")
                (valveSwitch 26 "2")
                (valveSwitch 27 "3")
                (valveSwitch 14 "4")
                (valveSwitch 12 "5")
                (valveSwitch 13 "6")
                {
                    platform = "gpio";
                    pin = 32;
                    name = "Waterfall Pump";
                    restore_mode = "RESTORE_DEFAULT_OFF";
                }
            ];
            valve = let
                mkValve = n: {
                    platform = "template";
                    name = "Valve Zone ${n}";
                    device_class = "water";
                    "open_action" = [{"switch.turn_on" = "valve_zone_${n}_sw";}];
                    "close_action" = [{"switch.turn_off" = "valve_zone_${n}_sw";}];
                    lambda = "if (id(valve_zone_${n}_sw).state) { return VALVE_OPEN; } else { return VALVE_CLOSED; }";
                };
            in
                map mkValve ["1" "2" "3" "4" "5" "6"];
            output = [
                {
                    platform = "gpio";
                    pin = 33;
                    id = "garden_light_output";
                }
            ];
            light = [
                {
                    platform = "binary";
                    name = "Garden Light";
                    output = "garden_light_output";
                    restore_mode = "RESTORE_DEFAULT_OFF";
                }
            ];
        };
    };
}
