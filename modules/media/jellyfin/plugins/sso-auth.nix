{lib, ...}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        jellyfinLib = import ../_lib.nix {inherit pkgs;};
        jf = config.services.jellyfin;
        version = "6.1.0.0";
        drv = jellyfinLib.mkPluginDrv {
            pname = "sso-auth";
            inherit version;
            guid = "505ce9d1-d916-42fa-86ca-673ef241d7df";
            jellyfinPackage = jf.package;
            zip = pkgs.fetchurl {
                url = "https://github.com/MaxRink/jellyfin-plugin-sso/releases/download/v${version}/sso-auth_${version}.zip";
                sha256 = "6311d6b16e89a91e44ce9b5a32c09d28eda292a11b75cd6b942d7bc62664cd00";
            };
        };
        install = jellyfinLib.installPlugin {
            inherit jf version drv;
            folderPrefix = "SSO-Auth";
        };
    in {
        systemd.tmpfiles.rules = install.tmpfilesRules;
        systemd.services.jellyfin.preStart = lib.mkAfter install.preStart;
    };
}
