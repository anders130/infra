{
    den.aspects.jellyfin.nixos = {pkgs, ...}: {
        my.services.jellyfin.plugins.merge-versions = rec {
            name = "Merge Versions";
            version = "12.0.0";
            guid = "f21bbed8-3a97-4d8b-88b2-48aaa65427cb";
            folderPrefix = "MergeVersions";
            zip = pkgs.fetchurl {
                url = "https://github.com/danieladov/jellyfin-plugin-mergeversions/releases/download/${version}/Jellyfin.Plugin.MergeVersions.zip";
                sha256 = "ccb6ea711dd529f2bba0d65aa3f0e9f432395861d8ea84a0fc2ed3d314767c8b";
            };
        };
    };
}
