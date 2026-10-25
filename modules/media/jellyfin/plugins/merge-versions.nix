{lib, ...}: {
    den.aspects.jellyfin.nixos = {
        config,
        pkgs,
        ...
    }: let
        jellyfinLib = import ../_lib.nix {inherit pkgs;};
        jf = config.services.jellyfin;
        version = "12.0.0";
        drv = jellyfinLib.mkPluginDrv {
            pname = "merge-versions";
            inherit version;
            guid = "f21bbed8-3a97-4d8b-88b2-48aaa65427cb";
            jellyfinPackage = jf.package;
            # No meta.json is bundled in the release zip -- it's normally
            # written by Jellyfin's own repository-install flow instead.
            extraMeta.name = "Merge Versions";
            zip = pkgs.fetchurl {
                url = "https://github.com/danieladov/jellyfin-plugin-mergeversions/releases/download/${version}/Jellyfin.Plugin.MergeVersions.zip";
                sha256 = "ccb6ea711dd529f2bba0d65aa3f0e9f432395861d8ea84a0fc2ed3d314767c8b";
            };
        };
        install = jellyfinLib.installPlugin {
            inherit jf version drv;
            folderPrefix = "MergeVersions";
        };
    in {
        systemd.tmpfiles.rules = install.tmpfilesRules;
        systemd.services.jellyfin.preStart = lib.mkAfter install.preStart;
    };
}
