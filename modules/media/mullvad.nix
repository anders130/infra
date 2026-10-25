{inputs, ...}: {
    flake-file.inputs.vpn-confinement.url = "github:Maroka-chan/VPN-Confinement";

    den.aspects.mullvad.nixos = {
        config,
        lib,
        ...
    }: {
        imports = [inputs.vpn-confinement.nixosModules.default];

        options.my.services.mullvad.bridgeAddress = lib.mkOption {
            type = lib.types.str;
            default = "192.168.15.1";
        };

        config = {
            sops.secrets."mullvad/wg_conf" = {
                sopsFile = config.my.secretFiles.mullvad;
                owner = "root";
                mode = "0400";
            };

            vpnNamespaces.mullvad = {
                enable = true;
                wireguardConfigFile = config.sops.secrets."mullvad/wg_conf".path;
            };

            networking.firewall.extraCommands = ''
                iptables -I FORWARD -o mullvad-br ! -i lo -j DROP
            '';
        };
    };
}
