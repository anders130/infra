{lib, ...}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        jellyfinLib = import ../_lib.nix {inherit pkgs;};
        jf = config.services.jellyfin;
        version = "3.0.1.0";
        drv = jellyfinLib.mkPluginDrv {
            pname = "file-transformation";
            inherit version;
            guid = "5e87cc92-571a-4d8d-8d98-d2d4147f9f90";
            jellyfinPackage = jf.package;
            extraMeta.name = "File Transformation";
            zip = pkgs.fetchurl {
                url = "https://github.com/IAmParadox27/jellyfin-plugin-file-transformation/releases/download/${version}/Release-12.0.0.zip";
                sha256 = "78defd17c35c07974ba77412201a1294a0137535b4802e08d778bd622dd4d692";
            };
        };
        install = jellyfinLib.installPlugin {
            inherit jf version drv;
            folderPrefix = "FileTransformation";
        };
    in {
        systemd.tmpfiles.rules = install.tmpfilesRules;
        systemd.services.jellyfin.preStart = lib.mkAfter install.preStart;
    };
}
