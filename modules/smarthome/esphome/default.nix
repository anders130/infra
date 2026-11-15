{
    serviceRegistry.esphome = {
        web = {
            subdomain = "esphome";
            port = 6052;
            protect = true;
        };
        dashboard = {
            name = "ESPHome";
            category = "Smart Home";
            widget = {
                type = "esphome";
                baseUrl = "http://127.0.0.1:6052";
            };
            resourceUnits = ["esphome.service"];
        };
    };

    den.aspects.esphome.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) converge getExe mkOption types;
        inherit (lib.modules) mkForce;
        inherit (lib.lists) elem;
        inherit (lib.strings) concatMapStringsSep optionalString;
        inherit (lib.attrsets) mapAttrsToList filterAttrsRecursive optionalAttrs;

        cfg = config.my.services.esphome;
        stateDir = "/var/lib/esphome";
        format = pkgs.formats.yaml {};

        # Adapted from https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/services/home-automation/home-assistant.nix
        mkESPConf = n: espCfg: let
            filteredConfig = converge (filterAttrsRecursive (_: v: ! elem v [null])) espCfg;
        in rec {
            name = "${n}-nix.yaml";
            file = pkgs.runCommandLocal name {} ''
                cp ${format.generate name filteredConfig} $out
                sed -i -e "s/'\!\([a-z_]\+\) \(.*\)'/\!\1 \2/;s/^\!\!/\!/;" $out
                sed -i 's/ {}//g' $out
                sed -i "s/'\"/\"/g" $out
                sed -i "s/\"'/\"/g" $out
            '';
        };
    in {
        options.my.services.esphome = {
            firmwareConfigs = mkOption {
                default = {};
                type = with types; attrsOf anything;
            };
            secretsFile = mkOption {
                default = null;
                type = types.nullOr types.path;
            };
        };

        config = {
            services.esphome.enable = true;

            services.avahi = {
                enable = true;
                nssmdns4 = true;
            };

            # Fixes https://github.com/NixOS/nixpkgs/issues/339557
            users = {
                users.esphome = {
                    isNormalUser = true;
                    isSystemUser = mkForce false;
                    group = "esphome";
                    extraGroups = ["dialout"];
                    home = stateDir;
                };
                groups.esphome = {};
            };

            systemd.services.esphome = {
                serviceConfig =
                    (optionalAttrs (cfg.firmwareConfigs != {}) {
                        ExecStartPre = getExe (pkgs.writeShellApplication {
                            name = "esphome-exec-start-pre";
                            runtimeInputs = [pkgs.findutils];
                            text = ''
                                shopt -s nullglob

                                for file in ${stateDir}/*-nix.yaml; do
                                    rm "$file"
                                done

                                ${optionalString
                                (cfg.secretsFile != null)
                                # bash
                                ''
                                    cp -f "$(realpath "${cfg.secretsFile}")" ${stateDir}/secrets.yaml
                                ''}

                                ${concatMapStringsSep
                                "\n"
                                (dev:
                                # bash
                                ''
                                    cp -f "$(realpath "${dev.file}")" ${stateDir}/"${dev.name}"
                                '')
                                (mapAttrsToList mkESPConf cfg.firmwareConfigs)}
                            '';
                        });
                    })
                    // {
                        # Fixes https://github.com/NixOS/nixpkgs/issues/339557
                        DynamicUser = mkForce "off";
                        # platformio bwrap wrapper always mkdir /tmp/.X11-unix before
                        # mounting tmpfs there; ProtectSystem=strict makes /tmp read-only
                        ReadWritePaths = ["/tmp"];
                    };
            };
        };
    };

    den.aspects.esphome.readme = {
        title = "ESPHome";
        intro = "ESPHome dashboard for managing ESP32/ESP8266 firmware.";
        sections = [
            {
                title = "Dependencies";
                content = ''
                    - [caddy](/modules/platform/caddy.nix)
                    - [sops](/modules/platform/sops)
                '';
            }
            {
                title = "Usage";
                content = ''
                    ```nix
                    den.aspects.<host>.includes = with den.aspects; [esphome];
                    my.services.esphome.firmwareConfigs.my-device = { ... };
                    my.services.esphome.secretsFile = config.sops.templates."esphome-secrets.yaml".path;
                    ```

                    Dashboard is served at `esphome.<domain>`.
                '';
            }
            {
                title = "Initial Flashing";
                content = ''
                    WebSerial (browser-based flashing) fails on CP2102-based boards — the
                    DTR/RTS auto-reset briefly disconnects the USB device, which WebSerial
                    cannot survive. Use `esptool` for the initial flash instead:

                    ```bash
                    # Download factory binary from the ESPHome dashboard first
                    esptool --port /dev/ttyUSB0 --chip esp32 --baud 115200 \
                        write-flash 0x0 firmware.factory.bin
                    ```

                    The user must be in the `dialout` group:

                    ```bash
                    sudo usermod -aG dialout $USER  # log out and back in after
                    ```

                    After the initial flash, all subsequent updates are done via OTA
                    from the ESPHome dashboard — no USB required.
                '';
            }
        ];
    };
}
