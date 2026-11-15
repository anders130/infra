{
    den.aspects.zigbee.nixos = {
        config,
        lib,
        pkgs,
        ...
    }: let
        inherit (lib) getExe mkOption types;
        cfg = config.my.services.zigbee;
    in {
        options.my.services.zigbee = {
            device = mkOption {
                type = types.str;
                default = "/dev/zigbee";
                description = "Serial device path (use stable udev symlink)";
            };
            port = mkOption {
                type = types.port;
                default = 20108;
            };
        };
        config = {
            systemd.services.zigbee = {
                description = "Zigbee serial-to-network proxy";
                wantedBy = ["multi-user.target"];
                after = ["network-online.target"];
                wants = ["network-online.target"];
                serviceConfig = {
                    ExecStart = "${getExe pkgs.ser2net} -n -c ${pkgs.writeText "ser2net.yaml" ''
                        connection: &zigbee
                            accepter: tcp,${toString cfg.port}
                            connector: serialdev,${cfg.device},115200n81,local
                    ''}";
                    Restart = "on-failure";
                    SupplementaryGroups = ["dialout"];
                };
            };
            services.udev.extraRules = ''
                SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", SYMLINK+="zigbee", MODE="0660", GROUP="dialout"
            '';
            networking.firewall.allowedTCPPorts = [cfg.port];
        };
    };
}
