{
    den.aspects.music-pi.nixos = {pkgs, ...}: {
        security.rtkit.enable = true;

        services.pipewire = {
            enable = true;
            alsa.enable = true;
            systemWide = true;
        };

        # Explicit codec list prevents AVDTP negotiation loops with Android 15
        # (Pixel 9 sends malformed AVDTP reject packets that BlueZ can't parse,
        # causing an endless START-reject retry cycle).
        services.pipewire.wireplumber.extraConfig."bluetooth.conf" = {
            "monitor.bluez.properties" = {
                "bluez5.roles" = ["a2dp_sink" "hfp_hf" "hfp_ag"];
                "bluez5.codecs" = ["sbc" "sbc_xq" "aac"];
                "bluez5.enable-sbc-xq" = true;
                "bluez5.enable-hw-volume" = true;
            };
        };

        systemd.services = {
            wireplumber.wantedBy = ["multi-user.target"];

            gmediarender.environment.PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
            librespot.environment.PIPEWIRE_RUNTIME_DIR = "/run/pipewire";
            shairport-sync.environment.PIPEWIRE_RUNTIME_DIR = "/run/pipewire";

            bt-agent = {
                description = "Bluetooth NoInputNoOutput pairing agent";
                after = ["bluetooth.service"];
                wantedBy = ["multi-user.target"];
                serviceConfig = {
                    ExecStart = "${pkgs.bluez-tools}/bin/bt-agent -c NoInputNoOutput";
                    Restart = "on-failure";
                };
            };

            bluetooth-init = {
                description = "Set Bluetooth adapter discoverable and pairable";
                after = ["bluetooth.service"];
                wantedBy = ["multi-user.target"];
                script = ''
                    until ${pkgs.bluez}/bin/bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; do
                        sleep 1
                    done
                    ${pkgs.bluez}/bin/bluetoothctl discoverable on
                    ${pkgs.bluez}/bin/bluetoothctl pairable on
                '';
                serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                };
            };
        };

        services.dbus.packages = [
            (pkgs.writeTextDir "share/dbus-1/system.d/pipewire-telephony.conf" ''
                <!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-BUS Bus Configuration 1.0//EN"
                    "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
                <busconfig>
                    <policy user="pipewire">
                        <allow own="org.pipewire.Telephony"/>
                    </policy>
                    <policy context="default">
                        <allow send_destination="org.pipewire.Telephony"/>
                    </policy>
                </busconfig>
            '')
        ];

        hardware.bluetooth = {
            enable = true;
            powerOnBoot = true;
            settings = {
                Policy.AutoEnable = true;
                General = {
                    DiscoverableTimeout = 0;
                    AlwaysPairable = true;
                    PairableTimeout = 0;
                    # Enables improved Android 14/15 A2DP compatibility code paths
                    Experimental = true;
                };
            };
        };
    };
}
