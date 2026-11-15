let
    sn = "oe010k60z24a0174";
    bat = n: "sensor.solplanet_battery_${sn}_${n}";
    meter = n: "sensor.solplanet_meter_${sn}_${n}";
in {
    den.aspects.ds1.nixos = {pkgs, ...}: let
        energyStorageFile = pkgs.writeText "hass-energy-storage" (builtins.toJSON {
            version = 1;
            minor_version = 3;
            key = "energy";
            data = {
                device_consumption = [
                    {
                        stat_consumption = "sensor.tv_dongle_summation_delivered";
                        name = "TV Wohnzimmer";
                    }
                    {
                        stat_consumption = "sensor.frient_a_s_splzb_141_summation_delivered";
                        name = "TV Jesse";
                    }
                    {
                        stat_consumption = "sensor.stehlampe_summation_delivered";
                        name = "Stehlampe";
                    }
                ];
                device_consumption_water = [];
                energy_sources = [
                    {
                        type = "solar";
                        stat_energy_from = bat "pv_energy_today";
                        stat_rate = bat "pv_power";
                        config_entry_solar_forecast = ["01KST0HCA1MV381P471CEF9GBG"];
                    }
                    {
                        type = "battery";
                        stat_energy_from = bat "battery_energy_for_discharging";
                        stat_energy_to = bat "battery_energy_for_charging";
                        stat_rate = bat "battery_power";
                        power_config.stat_rate = bat "battery_power";
                    }
                    {
                        type = "grid";
                        stat_energy_from = meter "grid_energy_in_today";
                        stat_energy_to = meter "grid_energy_out_today";
                        stat_cost = null;
                        stat_compensation = null;
                        entity_energy_price = null;
                        number_energy_price = null;
                        entity_energy_price_export = null;
                        number_energy_price_export = null;
                        cost_adjustment_day = 0.0;
                        stat_rate = meter "grid_power";
                        power_config.stat_rate = meter "grid_power";
                    }
                ];
            };
        });
    in {
        services.home-assistant.config.recorder.purge_keep_days = 730;
        services.home-assistant.config.history = {};
        services.home-assistant.config.energy = {};

        systemd.tmpfiles.settings."hass-energy" = {
            "/var/lib/hass/.storage" = {
                d = {
                    mode = "0700";
                    user = "hass";
                    group = "hass";
                };
            };
            "/var/lib/hass/.storage/energy" = {
                C = {
                    mode = "0600";
                    user = "hass";
                    group = "hass";
                    argument = "${energyStorageFile}";
                };
            };
        };
    };
}
