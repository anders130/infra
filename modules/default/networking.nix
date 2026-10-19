{lib, ...}: {
    den.default.nixos = {
        options.my.networking = {
            address = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Primary LAN IP address of this host, used by pihole for local DNS entries";
            };

            lanInterface = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = "Name of this host's interface on the home network";
            };
        };
    };
}
