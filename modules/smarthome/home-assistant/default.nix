{inputs, ...}: {
    # flake-file.inputs.lumehub-hacs = {
    #     url = "path:///home/jesse/Projects/Private/LumeHub/home-assistant";
    # };

    serviceRegistry."home-assistant" = {
        web = {
            subdomain = "home";
            port = 8123;
        };
        dashboard = {
            name = "Home Assistant";
            description = "Home automation";
            category = "Smart Home";
            widget = {
                type = "home-assistant";
                baseUrl = "http://127.0.0.1:8123";
                tokenEnvVar = "HASS_TOKEN";
                presets = ["people_home" "lights_on" "switches_on"];
            };
            resourceUnits = ["home-assistant.service"];
            widgetSecrets.HASS_TOKEN.name = "home-assistant/homepage_token";
        };
        access = {};
    };

    den.aspects.home-assistant.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) mapAttrs mapAttrsToList mkAfter mkOption types;
        cfg = config.my.services.home-assistant;
        dashboardFiles = mapAttrs (
            name: dash:
                (pkgs.formats.yaml {}).generate "${name}.yaml" dash.content
        )
        cfg.dashboards;

        lovelaceCards = with pkgs.home-assistant-custom-lovelace-modules; [
            mini-media-player
            mushroom
            button-card
            card-mod
            bubble-card
        ];

        lovelaceResources = builtins.toJSON (map (card: {
            id = "nix-${card.pname}";
            type = "module";
            url = "/local/nixos-lovelace-modules/${card.entrypoint or "${card.pname}.js"}";
        })
        lovelaceCards);
    in {
        options.my.services.home-assistant.dashboards = mkOption {
            type = types.attrsOf (types.submodule {
                options = {
                    title = mkOption {type = types.str;};
                    icon = mkOption {
                        type = types.str;
                        default = "mdi:view-dashboard";
                    };
                    show_in_sidebar = mkOption {
                        type = types.bool;
                        default = true;
                    };
                    content = mkOption {type = types.anything;};
                };
            });
            default = {};
        };
        config = {
            nixpkgs.overlays = [
                (_: prev: {
                    inherit
                        (inputs.unstable.legacyPackages.${prev.stdenv.hostPlatform.system})
                        home-assistant-custom-lovelace-modules
                        ;
                })
            ];

            services.home-assistant = {
                enable = true;
                package = inputs.unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system}.home-assistant;
                openFirewall = true;
                extraComponents = [
                    "esphome"
                    "met"
                    "mqtt"
                    "radio_browser"
                    "google_translate"
                    "stream"
                    "mobile_app"
                    "zha"
                    "music_assistant"
                    "dlna_dmr"
                    "yamaha_musiccast"
                    "fritz"
                    "fritzbox"
                    "isal"
                    "forecast_solar"
                    "qnap"
                    "systemmonitor"
                    "ipp"
                ];
                extraPackages = ps: [
                    ps.aioelectricitymaps
                    ps.forecast-solar
                    (ps.pyipp.overridePythonAttrs rec {
                        pname = "aioipp";
                        version = "0.19.3";
                        src = ps.fetchPypi {
                            inherit pname version;
                            hash = "sha256-/TjW2dpRDlqcoE1Je8vgnqt6qYdY5qgVk/PkHJuah4s=";
                        };
                        postPatch = "";
                        doCheck = false;
                    })
                ];
                customComponents = [
                    # inputs.lumehub-hacs.packages.${pkgs.stdenv.hostPlatform.system}.default
                    inputs.soundgate.packages.${pkgs.stdenv.hostPlatform.system}.hass-component
                ];
                customLovelaceModules = lovelaceCards;
                config.lovelace.dashboards = mapAttrs (name: dash: {
                    mode = "yaml";
                    filename = "${name}.yaml";
                    inherit (dash) title icon;
                    show_in_sidebar = dash.show_in_sidebar;
                })
                cfg.dashboards;
            };

            systemd.tmpfiles.rules = mapAttrsToList (
                name: file: "L+ /var/lib/hass/${name}.yaml - - - - ${file}"
            )
            dashboardFiles;

            systemd.services.home-assistant.reloadTriggers = builtins.attrValues dashboardFiles;

            systemd.services.home-assistant.preStart = mkAfter ''
                mkdir -p /var/lib/hass/.storage
                _res_file="/var/lib/hass/.storage/lovelace_resources"
                _nix_res='${lovelaceResources}'

                if [ -f "$_res_file" ]; then
                    _updated=$(${pkgs.jq}/bin/jq --argjson nix "$_nix_res" '
                        .data.items = ([.data.items[] | select(.id | startswith("nix-") | not)] + $nix)
                    ' "$_res_file")
                    [ -n "$_updated" ] && printf '%s' "$_updated" > "$_res_file"
                else
                    ${pkgs.jq}/bin/jq -n --argjson nix "$_nix_res" '{
                        "version": 1,
                        "minor_version": 1,
                        "key": "lovelace_resources",
                        "data": {"items": $nix}
                    }' > "$_res_file"
                fi
            '';
        };
    };
}
